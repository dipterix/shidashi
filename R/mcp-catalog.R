# ---- MCP tool catalog ----
#
# The MCP tool list is built from the template on disk, never from live
# sessions, so it is identical for every agent connection and does not
# change when browser tabs open or close. Each agent-enabled module is
# loaded once without a browser: its tool maker runs against a
# `shiny::MockShinySession` and only the schemas are kept. Live sessions
# provide the implementations at call time (see mcp-module.R).

mcp_module_property <- function() {
  list(
    type = "string",
    description = paste(
      "Optional; usually leave it out. The tool then runs in the module the",
      "user pinned or last used. This (implicit module ID) is recommended. ",
      "Only when the requested module or handle (from `shidashi_sessions`) ",
      "is different than the active handle, this input may be explicit."
    )
  )
}

mcp_intent_property <- function() {
  list(
    type = "string",
    description = "Brief explanation of why you are calling this tool."
  )
}

# Add an optional property to a tool schema
mcp_schema_add_property <- function(schema, name, property) {
  props <- schema$inputSchema$properties
  if (!length(props)) {
    props <- structure(list(), names = character(0))
  }
  props[[name]] <- property
  schema$inputSchema$type <- schema$inputSchema$type %||% "object"
  schema$inputSchema$properties <- props
  schema
}

# Modules whose agents.yaml enables agents
mcp_agent_modules <- function(root_path = template_root()) {
  module_ids <- module_info(root_path = root_path)$id
  module_ids[vapply(module_ids, function(module_id) {
    isTRUE(load_agent_conf(root_path = root_path, module_id = module_id)$enabled)
  }, FALSE)]
}

#' Harvest the tool schemas of one module without a browser
#' @return `list(ok, tools, error)` where `tools` is a named list of MCP tool
#'   schemas (`name`, `description`, `inputSchema`)
#' @noRd
mcp_harvest_module <- function(module_id, root_path = template_root()) {
  tryCatch(
    {
      res <- load_module_resource(
        root_path = root_path,
        module_id = module_id,
        env = new.env(parent = globalenv())
      )
      tool_maker <- res$environment$.mcptools_maker
      if (!is.function(tool_maker)) {
        stop("Module `", module_id, "` does not define any agent tools.")
      }
      mock_session <- shiny::MockShinySession$new()
      on.exit(mock_session$close(), add = TRUE)
      tools <- shiny::withReactiveDomain(mock_session, {
        tool_maker(mock_session)
      })
      schemas <- lapply(tools$as_list(), ellmer_tool_schema)
      list(ok = TRUE, tools = schemas[sort(names(schemas))], error = NULL)
    },
    error = function(e) {
      list(ok = FALSE, tools = list(), error = conditionMessage(e))
    }
  )
}

# Schema for a tool that could not be harvested: `agents/tool-schema.yaml`
# for tools, the skill folder for skills. Returns NULL when unknown.
mcp_fallback_schema <- function(tool_name, root_path = template_root()) {
  skill_parts <- regmatches(
    tool_name, regexec("^skill_(load|run)__(.+)$", tool_name)
  )[[1L]]
  if (length(skill_parts)) {
    role <- skill_parts[[2L]]
    skill_dir <- file.path(root_path, "agents", "skills", skill_parts[[3L]])
    if (!file.exists(file.path(skill_dir, "SKILL.md"))) {
      return(NULL)
    }
    # A skill without scripts has no run tool
    skill_tool <- tryCatch(skill_wrapper(skill_dir)()[[role]],
                           error = function(e) NULL)
    if (!inherits(skill_tool, "ellmer::ToolDef")) {
      return(NULL)
    }
    skill_tool <- wrap_tools_with_permissions(tool = skill_tool, session = NULL)
    return(ellmer_tool_schema(skill_tool))
  }

  schema_path <- file.path(root_path, "agents", "tool-schema.yaml")
  if (!file.exists(schema_path)) {
    return(NULL)
  }
  conf <- tryCatch(yaml::read_yaml(schema_path), error = function(e) NULL)
  short_name <- sub("^tool__", "", tool_name)
  for (item in conf$tools) {
    if (identical(item$name, short_name)) {
      schema <- list(
        name        = tool_name,
        description = item$description %||% "",
        inputSchema = item$inputSchema %||% list(type = "object")
      )
      # keep a single required name as a JSON array
      if (length(schema$inputSchema$required)) {
        schema$inputSchema$required <- as.list(schema$inputSchema$required)
      }
      return(mcp_schema_add_property(schema, "_intent", mcp_intent_property()))
    }
  }
  NULL
}

# Digest of the template files that can change the tool list
mcp_template_fingerprint <- function(root_path = template_root()) {
  files <- c(
    file.path(root_path, "modules.yaml"),
    list.files(file.path(root_path, "R"), recursive = TRUE, full.names = TRUE),
    list.files(file.path(root_path, "agents"), recursive = TRUE,
               full.names = TRUE),
    list.files(file.path(root_path, "modules"),
               pattern = "(\\.[Rr]|agents\\.yaml)$",
               recursive = TRUE, full.names = TRUE)
  )
  files <- sort(unique(files[file.exists(files)]))
  info <- file.info(files, extra_cols = FALSE)
  digest::digest(list(files, as.numeric(info$mtime), info$size))
}

# Per-tool settings from a module's agents.yaml, keyed by MCP tool name:
# `enabled`, `category`, and (for skill run tools) `scripts`. Reading a
# skill (`skill_load__`) never changes anything, whatever the skill's
# category; its scripts decide whether running it (`skill_run__`) does.
mcp_module_tool_settings <- function(root_path, module_id) {
  conf <- load_agent_conf(root_path = root_path, module_id = module_id)
  settings <- list()
  for (item in conf$tools) {
    if (length(item$name) != 1L) next
    settings[[sprintf("tool__%s", item$name)]] <- list(
      enabled  = item$enabled,
      category = as.character(unlist(item$category)),
      scripts  = list()
    )
  }
  for (item in conf$skills) {
    if (length(item$name) != 1L) next
    settings[[sprintf("skill_load__%s", item$name)]] <- list(
      enabled  = item$enabled,
      category = "exploratory",
      scripts  = list()
    )
    settings[[sprintf("skill_run__%s", item$name)]] <- list(
      enabled  = item$enabled,
      category = as.character(unlist(item$category)),
      scripts  = as.list(item$scripts)
    )
  }
  settings
}

# Agent modes do not apply to MCP; only `enabled: no` (or no `enabled`)
# turns a tool off
mcp_tool_turned_on <- function(setting) {
  !is.null(setting$enabled) && !isFALSE(setting$enabled)
}

mcp_destructive_categories <- c("destructive", "needs_confirmation")

# Hints for one module's settings of a tool
mcp_tool_hints <- function(setting) {
  destructive_scripts <- unlist(lapply(setting$scripts, function(script) {
    if (any(mcp_destructive_categories %in% unlist(script$category))) {
      as.character(script$name)
    }
  }))
  destructive <- any(mcp_destructive_categories %in% setting$category)
  list(
    destructive         = destructive,
    destructive_scripts = as.character(destructive_scripts),
    read_only           = !destructive && !length(destructive_scripts) &&
      length(setting$category) > 0L && all(setting$category == "exploratory")
  )
}

# Mark a schema with MCP tool annotations, and add a note the model reads.
# `hints` holds one mcp_tool_hints() result per module offering the tool: a
# tool is destructive if any module says so, read-only if all modules do.
mcp_apply_hints <- function(schema, hints) {
  destructive <- any(vapply(hints, `[[`, FALSE, "destructive"))
  scripts <- unique(unlist(lapply(hints, `[[`, "destructive_scripts")))
  read_only <- length(hints) > 0L && all(vapply(hints, `[[`, FALSE, "read_only"))

  schema$annotations <- list(
    readOnlyHint    = read_only,
    destructiveHint = destructive || length(scripts) > 0L
  )

  note <- NULL
  if (destructive) {
    note <- paste(
      "This tool can change or remove the user's work.",
      "Ask the user in this conversation before calling it."
    )
  } else if (length(scripts)) {
    note <- sprintf(
      paste(
        "Running these scripts can change or remove the user's work, so ask",
        "the user in this conversation before running them: %s."
      ),
      paste(sprintf("`%s`", scripts), collapse = ", ")
    )
  }
  if (length(note)) {
    schema$description <- paste0(
      paste(schema$description, collapse = "\n"), "\n\n", note
    )
  }
  schema
}

# The name a tool gets when modules disagree on it, e.g. `tool__hello` in
# module `beta` is listed as `tool__beta__hello`
mcp_qualified_tool_name <- function(tool_name, module_id) {
  sub("^(tool|skill_load|skill_run)__", sprintf("\\1__%s__", module_id),
      tool_name)
}

mcp_build_catalog <- function(root_path) {
  module_ids <- mcp_agent_modules(root_path = root_path)
  settings <- structure(
    lapply(module_ids, function(module_id) {
      mcp_module_tool_settings(root_path = root_path, module_id = module_id)
    }),
    names = module_ids
  )
  module_hints <- function(tool_name, modules) {
    lapply(modules, function(module_id) {
      mcp_tool_hints(settings[[module_id]][[tool_name]])
    })
  }

  # tool name -> list of variants, each list(key, schema, modules)
  variants <- list()
  add_variant <- function(schema, module_id) {
    key <- digest::digest(list(schema$description, schema$inputSchema))
    existing <- variants[[schema$name]]
    for (ii in seq_along(existing)) {
      if (identical(existing[[ii]]$key, key)) {
        existing[[ii]]$modules <- c(existing[[ii]]$modules, module_id)
        variants[[schema$name]] <<- existing
        return(invisible())
      }
    }
    variants[[schema$name]] <<- c(existing, list(list(
      key = key, schema = schema, modules = module_id
    )))
    invisible()
  }

  errors <- list()
  for (module_id in module_ids) {
    harvested <- mcp_harvest_module(module_id, root_path = root_path)
    if (!harvested$ok) {
      errors[[module_id]] <- harvested$error
      next
    }
    for (schema in harvested$tools) {
      if (mcp_tool_turned_on(settings[[module_id]][[schema$name]])) {
        add_variant(schema, module_id)
      }
    }
  }

  # Modules that failed to load still offer the tools their agents.yaml
  # lists: attach them to an unambiguous harvested schema, or fall back to
  # the schemas declared on disk.
  for (module_id in names(errors)) {
    tool_names <- names(Filter(mcp_tool_turned_on, settings[[module_id]]))
    for (tool_name in tool_names) {
      existing <- variants[[tool_name]]
      if (length(existing) == 1L) {
        existing[[1L]]$modules <- c(existing[[1L]]$modules, module_id)
        variants[[tool_name]] <- existing
      } else if (!length(existing)) {
        schema <- mcp_fallback_schema(tool_name, root_path = root_path)
        if (!is.null(schema)) {
          add_variant(schema, module_id)
        }
      }
    }
  }

  tools <- list()
  for (tool_name in names(variants)) {
    tool_variants <- variants[[tool_name]]
    if (length(tool_variants) == 1L) {
      variant <- tool_variants[[1L]]
      tools[[tool_name]] <- list(
        name      = tool_name,
        live_name = tool_name,
        modules   = variant$modules,
        schema    = mcp_schema_add_property(
          mcp_apply_hints(variant$schema,
                          module_hints(tool_name, variant$modules)),
          "_module", mcp_module_property()
        )
      )
      next
    }
    warning(
      "Tool `", tool_name, "` has different arguments in different ",
      "modules; it is listed once per module as `<type>__<module>__<name>`.",
      call. = FALSE
    )
    for (variant in tool_variants) {
      for (module_id in variant$modules) {
        qualified_name <- mcp_qualified_tool_name(tool_name, module_id)
        schema <- variant$schema
        schema$name <- qualified_name
        tools[[qualified_name]] <- list(
          name      = qualified_name,
          live_name = tool_name,
          modules   = module_id,
          schema    = mcp_schema_add_property(
            mcp_apply_hints(schema, module_hints(tool_name, module_id)),
            "_module", mcp_module_property()
          )
        )
      }
    }
  }

  list(tools = tools[sort(names(tools))], errors = errors)
}

#' The MCP tool catalog of a template
#' @param root_path template root
#' @param refresh whether to ignore the cache
#' @return `list(tools, errors, fingerprint)`. `tools` is a named list; each
#'   element has `name`, `live_name` (the tool name inside live sessions),
#'   `modules` (module ids that offer it), and `schema` (MCP tool schema).
#' @noRd
mcp_catalog <- function(root_path = template_root(), refresh = FALSE) {
  root_path <- normalizePath(root_path, mustWork = TRUE, winslash = "/")
  fingerprint <- mcp_template_fingerprint(root_path)

  cache <- NULL
  globals <- get_shidashi_globals()
  if (is.environment(globals)) {
    if (!is_shidashi_fastmap(globals$mcp_catalog_cache)) {
      globals$mcp_catalog_cache <- new_fastmap()
    }
    cache <- globals$mcp_catalog_cache
  }

  if (!refresh && !is.null(cache)) {
    cached <- cache$get(root_path)
    if (identical(cached$fingerprint, fingerprint)) {
      return(cached)
    }
  }

  catalog <- mcp_build_catalog(root_path)
  catalog$fingerprint <- fingerprint
  if (!is.null(cache)) {
    cache$set(root_path, catalog)
  }
  catalog
}

# Tools that are always listed, independent of the template
mcp_meta_tool_schemas <- function() {
  empty_object <- structure(list(), names = character(0))
  list(
    list(
      name = "shidashi_sessions",
      description = paste(
        "Show what the app is for, which dashboard modules are open, and the",
        "`default_module`: the module the user pinned or last used, where",
        "tools run unless `_module` says otherwise. Also lists modules that",
        "are not open. Call it first, and again when unsure which module the",
        "user is working in."
      ),
      inputSchema = list(type = "object", properties = empty_object)
    ),
    list(
      name = "shidashi_tools",
      description = paste(
        "List the app's tools with their descriptions and arguments: the",
        "same tools your tool list shows once it refreshes. Use it with",
        "`shidashi_call` when your tool list did not refresh after",
        "connecting to or launching an app."
      ),
      inputSchema = list(type = "object", properties = empty_object)
    ),
    list(
      name = "shidashi_call",
      description = paste(
        "Call a tool by name in an open dashboard module. Only needed for",
        "tools that are not in your tool list. Use `shidashi_tools` to see",
        "the tools and their arguments."
      ),
      inputSchema = list(
        type = "object",
        properties = list(
          tool = list(
            type = "string",
            description = "Tool name, e.g. `tool__my_tool`."
          ),
          arguments = list(
            type = "object",
            description = paste(
              "Arguments for the tool. A JSON-encoded string is also accepted."
            )
          ),
          `_module` = mcp_module_property()
        ),
        required = list("tool")
      )
    )
  )
}
