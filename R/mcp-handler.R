# ---- MCP method handlers ----
#
# `tools/list` returns the same list to every agent connection: the meta
# tools plus the catalog harvested from the template (mcp-catalog.R).
# `tools/call` chooses the open module for each call independently
# (mcp-module.R) and runs the tool implementation from that module's
# session. Agent modes and the confirmation policy belong to the
# in-dashboard chat: over MCP, tools only carry hints (read-only,
# destructive) and the agent asks the user in its own chat. The shared
# tool wrapper (`wrap_tools_with_permissions`) tells the two routes apart
# with `mcp_call_active()`.

# Set while an MCP tool call runs, so the shared tool wrapper can skip
# the chat's mode checks and confirmation dialogs. A flag rather than an
# argument: a chat model cannot set it.
mcp_call_active <- local({

  # Must be NULL to avoid embedding environment in the build package
  active <- FALSE

  function(v) {
    if (!missing(v)) {
      active <<- isTRUE(v)
    }
    active
  }
  
})


# Instructions sent to agents on `initialize`. With `app_id = NULL` the text
# names no app; the stdio proxy uses that variant (see setup_mcp_proxy).
mcp_server_instructions <- function(app_id = mcp_app_id()) {
  first <- if (length(app_id)) {
    sprintf("This server drives a shiny dashboard (app `%s`)", app_id)
  } else {
    "This server drives a shiny dashboard"
  }
  paste(
    first,
    "via `shidashi` (Github `dipterix/shidashi`) package. ",
    "The shidashi package offers a MCP server framework for shiny apps. ",
    "The tools offered by each app is different. ",
    "Call `shidashi_sessions` first: it says what this app is for, which " ,
    "modules are open, and which one is the default module. ",
    "\n\n",
    "## General rules:\n",
    "1. Each shidashi app contains multiple separately operated modules (sub-apps). ",
    "By default, tools run in the default module chosen by the following criteria: ",
    "the module the user pinned, otherwise ",
    "the one they used most recently. Working in the default module is" ,
    "always recommended: this can be done by leaving out `_module` argument. \n",
    "2. Unless the user asks for a different module or the tool is not available in the default one, ",
    "do not reuse a handle from earlier calls: since ",
    "the user may have switched or pinned another module (they have switched to a new module but you are still operating on the old module). ",
    "3. If a result's note says the requested handle is different from the current one, ",
    "double-check with the user. ",
    "Every result ends with a note naming the module it ran on. \n",
    "4. Tools marked destructive change the user's work: ask the user for in this ",
    "conversation for confirmation before calling them. \n",
    "5. To show the user another module, or open one, call `switch_module`. ",
    "Switch modules only if the user asked for it, or a skill or protocol permits it.",
    "If you are not sure, tell the user your plan and ask for permission (one-time permission is fine),",
    "for example, 'The procedure requires switching between modules [list the module IDs].",
    "Please confirm that this is OK; otherwise I will only work on the current module.'"
  )
}

mcp_handle_initialize <- function(id, params) {
  pkg_version <- tryCatch(
    as.character(utils::packageVersion("shidashi")),
    error = function(e) "0.0.0"
  )
  mcp_json_result(id, list(
    protocolVersion = "2025-03-26",
    capabilities    = list(tools = list(listChanged = FALSE)),
    serverInfo      = list(name = "shidashi", version = pkg_version),
    instructions    = mcp_server_instructions()
  ))
}

# The app's own tools (no meta tools), as MCP tool schemas
mcp_app_tool_schemas <- function() {
  catalog <- tryCatch(mcp_catalog(), error = function(e) {
    warning("Cannot build the MCP tool catalog: ", conditionMessage(e),
            call. = FALSE)
    list(tools = list())
  })
  unname(lapply(catalog$tools, `[[`, "schema"))
}

mcp_handle_tools_list <- function(id, params) {
  tools <- c(mcp_meta_tool_schemas(), mcp_app_tool_schemas())
  mcp_json_result(id, list(tools = tools))
}

# The `shidashi_tools` meta tool: what `tools/list` adds for this app, for
# clients whose tool list did not refresh
mcp_tool_tools <- function() {
  list(
    content = list(list(
      type = "text",
      text = as.character(jsonlite::toJSON(
        mcp_app_tool_schemas(), auto_unbox = TRUE, null = "null"
      ))
    )),
    isError = FALSE
  )
}

mcp_handle_tools_call <- function(id, params, scope = list()) {
  tool_name <- params$name
  arguments <- params$arguments
  if (!is.list(arguments)) {
    arguments <- list()
  }

  if (!is.character(tool_name) || length(tool_name) != 1L) {
    return(mcp_json_error(id, -32602L,
                          "Invalid params: missing or invalid tool name"))
  }

  result <- switch(
    tool_name,
    "shidashi_sessions" = mcp_tool_sessions(scope),
    "shidashi_tools"    = mcp_tool_tools(),
    "switch_module"     = mcp_tool_switch_module(arguments, scope),
    "shidashi_call" = {
      inner_arguments <- arguments$arguments
      if (is.character(inner_arguments)) {
        inner_arguments <- tryCatch(
          jsonlite::fromJSON(inner_arguments, simplifyDataFrame = FALSE,
                             simplifyMatrix = FALSE),
          error = function(e) e
        )
      }
      if (inherits(inner_arguments, "error")) {
        mcp_tool_error(paste0(
          "`arguments` is not valid JSON: ", conditionMessage(inner_arguments)
        ))
      } else {
        if (!is.list(inner_arguments)) {
          inner_arguments <- list()
        }
        inner_arguments[["_module"]] <- arguments[["_module"]]
        mcp_call_tool(arguments$tool, inner_arguments, scope,
                      use_catalog = FALSE)
      }
    },
    mcp_call_tool(tool_name, arguments, scope)
  )

  if (promises::is.promise(result)) {
    return(promises::then(result, function(res) mcp_json_result(id, res)))
  }
  mcp_json_result(id, result)
}

mcp_tool_error <- function(message) {
  list(
    content = list(list(type = "text", text = message)),
    isError = TRUE
  )
}

# Choose the open module for `tool_name` and run the tool there
mcp_call_tool <- function(tool_name, arguments, scope = list(),
                          use_catalog = TRUE) {
  if (!is.character(tool_name) || length(tool_name) != 1L ||
      !nzchar(tool_name)) {
    return(mcp_tool_error("A tool name is required."))
  }

  module <- arguments[["_module"]]
  arguments[["_module"]] <- NULL

  catalog_entry <- NULL
  if (use_catalog) {
    catalog_entry <- tryCatch(mcp_catalog()$tools[[tool_name]],
                              error = function(e) NULL)
  }
  live_name <- catalog_entry$live_name %||% tool_name
  providers <- catalog_entry$modules

  # A module-qualified name (`tool__<module>__<name>`) only runs in its module
  qualified <- !identical(live_name, tool_name) && length(providers) == 1L

  resolved <- mcp_resolve_module(
    tool_name = live_name,
    module = module,
    scope_module = scope$module,
    providers = providers,
    only_modules = if (qualified) providers
  )
  if (!isTRUE(resolved$ok)) {
    return(mcp_tool_error(resolved$message))
  }

  # `_module` points away from the current module: a pinned module wins;
  # otherwise run, but tell the agent to double-check
  reason <- resolved$reason
  if (identical(reason, "requested") &&
      !identical(resolved$handle, resolved$default_handle)) {
    if (identical(resolved$default_reason, "pinned")) {
      return(mcp_tool_error(sprintf(
        paste(
          "The user pinned `%1$s`, so tool calls must run there, but",
          "`_module` asked for `%2$s`. Nothing ran. Call the tool again",
          "without `_module`. If the user really wants `%2$s`, ask them to",
          "pin that module (or unpin the current module) in the dashboard. ",
          "Do NOT use the raw handler: the user will not understand it. You can kindly ask the followings instead: ",
          "\"Another different module [ID: `%3$s`] has already be pinned to front. This prevents me from making current request to module [ID: `%4$s`]. ",
          "Please unpin the module to proceed.\""
        ),
        resolved$default_handle, resolved$handle, 
        gsub("@.*$", "", resolved$default_handle),
        gsub("@.*$", "", resolved$handle)
      )))
    }
    reason <- sprintf(
      paste(
        "requested handle is different from the current active handle %s,",
        "%s; double-check this is the module the user means"
      ),
      resolved$default_handle, resolved$default_reason
    )
  }

  tool_obj <- resolved$entry$tools$get(live_name)
  note <- list(type = "text", text = sprintf(
    "[shidashi] ran on %s (%s)", resolved$handle, reason
  ))
  add_note <- function(result) {
    result$content <- c(result$content, list(note))
    result
  }

  mcp_call_active(TRUE)
  on.exit(mcp_call_active(FALSE), add = TRUE)
  result <- ellmer_tool_call(tool_obj, arguments, provider = get_mcp_provider())
  if (promises::is.promise(result)) {
    return(promises::then(result, add_note))
  }
  add_note(result)
}

# The app's optional `welcome` text from `agents/tool-schema.yaml`, as
# `list(welcome = ...)`, or an empty list. App developers use it to tell
# agents what the app is for.
mcp_app_welcome <- function(root_path = template_root()) {
  path <- file.path(root_path, "agents", "tool-schema.yaml")
  if (!file.exists(path)) {
    return(list())
  }
  welcome <- tryCatch(yaml::read_yaml(path)$welcome, error = function(e) NULL)
  welcome <- trimws(paste(as.character(unlist(welcome)), collapse = "\n"))
  if (!nzchar(welcome)) {
    return(list())
  }
  list(welcome = welcome)
}

# The `shidashi_sessions` meta tool. It reports no server paths.
mcp_tool_sessions <- function(scope = list()) {
  open_modules <- mcp_rank_modules(
    mcp_match_modules(mcp_open_modules(), scope$module)
  )
  modules <- tryCatch(module_info(), error = function(e) NULL)
  module_label <- function(module_id) {
    label <- modules$label[match(module_id, modules$id)]
    if (length(label) != 1L || is.na(label)) "" else label
  }

  catalog <- tryCatch(mcp_catalog(), error = function(e) list(tools = list()))
  agent_modules <- unique(unlist(lapply(catalog$tools, `[[`, "modules")))
  open_ids <- vapply(open_modules, `[[`, "", "module_id")

  default_module <- NULL
  if (length(open_modules)) {
    default_module <- list(
      handle = open_modules[[1L]]$handle,
      reason = mcp_module_reason(open_modules[[1L]])
    )
  }

  info <- list(
    app = c(list(app_id = mcp_app_id()), mcp_app_welcome()),
    default_module = default_module,
    open_modules = lapply(seq_along(open_modules), function(ii) {
      open_module <- open_modules[[ii]]
      activity <- open_module$entry$activity
      last_used <- NULL
      if (inherits(activity$get("focused_at"), "POSIXct")) {
        last_used <- format(activity$get("focused_at"), "%Y-%m-%dT%H:%M:%S")
      }
      list(
        handle    = open_module$handle,
        module_id = open_module$module_id,
        label     = module_label(open_module$module_id),
        default   = ii == 1L,
        pinned    = isTRUE(activity$get("pinned", FALSE)),
        last_used = last_used,
        tools     = as.list(sort(open_module$entry$tools$keys()))
      )
    }),
    modules_not_open = as.list(setdiff(agent_modules, open_ids))
  )

  list(
    content = list(list(
      type = "text",
      text = as.character(jsonlite::toJSON(
        info, auto_unbox = TRUE, null = "null", pretty = TRUE
      ))
    )),
    isError = FALSE
  )
}

# ---------- ellmer bridges ---------------------------------------------------

ellmer_tool_schema <- function(tool_obj) {
  # Do NOT remove
  # DIPSAUS DEBUG START
  # tool_obj <- ellmer::tool(
  #   rnorm,
  #   description = "Draw numbers from a random normal distribution",
  #   arguments = list(
  #     n = ellmer::type_integer("The number of observations. Must be a positive integer."),
  #     mean = ellmer::type_number("The mean value of the distribution."),
  #     sd = ellmer::type_number("The standard deviation of the distribution. Must be a non-negative number.")
  #   )
  # )

  ellmer <- asNamespace("ellmer")

  provider_args <- list(name = "dummy", base_url = "https://dummy")
  # `model` is deprecated in newer ellmer, but may be required by older ones
  if (is.call(formals(ellmer::Provider)$model)) {
    provider_args$model <- "dummy"
  }
  dummy_provider <- do.call(ellmer::Provider, provider_args)
  schema <- ellmer$as_json(dummy_provider, tool_obj@arguments)
  # Remove OpenAI-specific quirks if any
  schema$additionalProperties <- NULL

  list(
    name = tool_obj@name,
    description = tool_obj@description,
    inputSchema = schema
  )
}

#' Call a ToolDef with MCP arguments
#'
#' Splices the JSON arguments into the ToolDef's callable interface.
#' Returns MCP result format.
#' @keywords internal
#' @noRd
ellmer_tool_call <- function(tool_obj, arguments, provider = NULL) {
  if (is.null(arguments)) arguments <- list()

  # ToolDef inherits from class_function — it's directly callable
  # Call with the arguments from JSON

  tool_error <- function(e) {
    list(
      content = list(list(
        type = "text",
        text = paste0("Error executing tool '", tool_obj@name, "': ",
                      conditionMessage(e))
      )),
      isError = TRUE
    )
  }

  tryCatch({
    ret <- do.call(tool_obj, arguments)

    # Handle promises (async tools like shiny_query_ui)
    if (promises::is.promise(ret)) {
      return(promises::then(
        ret,
        onFulfilled = function(value) {
          content_to_mcp(value, provider)
        },
        onRejected = tool_error
      ))
    }

    content_to_mcp(ret, provider)
  }, error = tool_error)

}

