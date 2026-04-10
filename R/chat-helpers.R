#' Create an \pkg{ellmer} Chat object for the chat-bot
#'
#' @description
#' Factory function that creates an \code{ellmer::Chat} object based on
#' the configured provider.  Reads from
#' \code{options(shidashi.chat_provider)}, \code{shidashi.chat_model},
#' and \code{shidashi.chat_base_url}. These arguments are passed to
#' \code{\link[ellmer]{chat}}.
#'
#' @param system_prompt character; the system prompt.  Defaults to
#'   \code{getOption("shidashi.chat_system_prompt")}.
#' @param provider character; provider name or provider name with models.
#'   Defaults to \code{getOption("shidashi.chat_provider", "anthropic")}.
#' @param base_url character or \code{NULL}; base URL for
#'   API-compatible providers.
#' @return An \code{ellmer::Chat} R6 object (tools not yet bound).
#' @keywords internal
init_chat <- function(
    system_prompt = getOption("shidashi.chat_system_prompt", NULL),
    provider = getOption("shidashi.chat_provider", "anthropic"),
    # model = getOption("shidashi.chat_model", NULL),
    base_url = getOption("shidashi.chat_base_url", NULL)
) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Package 'ellmer' is required for the chatbot feature.")
  }

  if (!length(system_prompt)) {
    system_prompt <- paste(
      "You are an R Shiny expert. You have access to the shiny",
      "application via provided tools."
    )
  }

  provider <- tolower(provider)

  # Build args common to most providers
  args <- list(system_prompt = system_prompt,
               name = provider,
               echo = "output")
  # if (length(model) == 1L && nzchar(model)) {
  #   args$model <- model
  # }
  if (length(base_url) == 1L && nzchar(base_url)) {
    args$base_url <- base_url
  }
  do.call(ellmer::chat, args)
}



#' Check if a tool is enabled for a given mode
#' @param tool an ellmer::ToolDef with shidashi annotations
#' @param mode character scalar: the current mode name
#' @return logical
#' @keywords internal
#' @noRd
is_tool_enabled_for_mode <- function(tool, mode) {
  enabled <- tool@annotations$shidashi_enabled
  if (is.null(enabled)) return(FALSE)
  if (isTRUE(enabled)) return(TRUE)
  if (isFALSE(enabled)) return(FALSE)
  # enabled is a character vector (or list) of mode names
  mode %in% as.character(unlist(enabled))
}

#' Check if a skill script is enabled for a given mode
#' @param skill_scripts list of per-script override configs from agents.yaml
#' @param script_name character scalar: the script filename
#' @param mode character scalar: the current mode name
#' @return logical
#' @keywords internal
#' @noRd
is_script_enabled_for_mode <- function(skill_scripts, script_name, mode) {
  if (!length(skill_scripts)) return(TRUE)
  for (sc in skill_scripts) {
    if (identical(sc$name, script_name)) {
      enabled <- sc$enabled
      if (is.null(enabled)) return(TRUE)
      if (isTRUE(enabled)) return(TRUE)
      if (isFALSE(enabled)) return(FALSE)
      return(mode %in% as.character(unlist(enabled)))
    }
  }
  TRUE
}

#' Get the category list for a specific skill script
#' @keywords internal
#' @noRd
get_script_category <- function(skill_scripts, script_name) {
  if (!length(skill_scripts)) return(character(0))
  for (sc in skill_scripts) {
    if (identical(sc$name, script_name)) {
      return(as.character(unlist(sc$category)))
    }
  }
  character(0)
}

load_agent_conf <- function(root_path, module_id) {
  root_path <- normalizePath(root_path, mustWork = TRUE)
  module_root <- file.path(root_path, "modules", module_id)
  agent_conf_path <- file.path(module_root, "agents.yaml")
  # read agent.yaml
  if (file.exists(agent_conf_path)) {
    agent_conf <- yaml::read_yaml(agent_conf_path)
    agent_conf$parameters <- as.list(agent_conf$parameters)
    if (!length(agent_conf$parameters$system_prompt)) {
      agent_conf$parameters$system_prompt <- paste(
        "You are an R shiny expert. You have access to the shiny",
        "application via provided tools."
      )
    }
    # Top-level enabled flag: default TRUE when agents.yaml exists
    if (is.null(agent_conf$enabled)) {
      agent_conf$enabled <- TRUE
    } else {
      agent_conf$enabled <- isTRUE(agent_conf$enabled)
    }
  } else {
    # agents.yaml missing → agents disabled for this module
    agent_conf <- list(
      enabled = FALSE,
      tools = list(
        # list(
        #   name = "hello_world",
        #   category = list("exploratory"),
        #   enabled = TRUE
        # ),
        # list(
        #   name = "get_shiny_input_values",
        #   category = list("exploratory"),
        #   enabled = TRUE
        # )
      ),
      skills = list(),
      parameters = list(
        system_prompt = paste(
          "You are a helpful assistant."
        )
      )
    )
  }
  agent_conf
}

compile_tools_and_scripts <- function(root_path, module_id, env) {
  root_path <- normalizePath(root_path, mustWork = TRUE)
  agent_conf <- load_agent_conf(root_path = root_path, module_id = module_id)
  # ---- Register MCP tools ----

  tool_names <- unlist(lapply(agent_conf$tools, "[[", "name"))
  names(agent_conf$tools) <- tool_names

  skill_names <- unlist(lapply(agent_conf$skills, "[[", "name"))
  if (length(agent_conf$skills)) {
    names(agent_conf$skills) <- skill_names
  }

  vnames <- ls(env, all.names = TRUE)
  tools <- lapply(vnames, function(vname) {
    value <- env[[vname]]
    if (!is.function(value)) { return() }
    if (inherits(value, "ellmer::ToolDef")) { return(value) }
    if (inherits(value, "shidashi_mcp_wrapper")) { return(value) }
    return(NULL)
  })

  tools <- drop_null(tools)

  # ---- Discover skill directories (Phase 4) ----
  # Per Anthropic spec, skill name == folder name. Direct lookup,
  # no iteration needed. Missing folders are silently dropped.
  skill_wrappers <- list()
  if (length(skill_names)) {
    root_skills_dir <- file.path(root_path, "agents", "skills")
    for (sname in skill_names) {
      skill_dir <- file.path(root_skills_dir, sname)
      if (file.exists(file.path(skill_dir, "SKILL.md"))) {
        skill_wrappers[[sname]] <- skill_wrapper(skill_dir)
      }
    }
  }

  # Phase 7: mode-getter closure for tool annotations
  get_current_mode <- function() {
    globals_get_agent_mode(module_id = module_id)
  }

  # create a tool-generating function
  tool_gen_fun <- function(session) {

    tool_map <- fastmap::fastmap()
    lapply(tools, function(tool) {
      toolset <- list()
      if (inherits(tool, "ellmer::ToolDef")) {
        toolset <- list(tool)
      } else {
        # generator
        toolset <- tool(session = session)
        if (inherits(toolset, "ellmer::ToolDef")) {
          toolset <- list(toolset)
        }
      }

      lapply(toolset, function(tool) {
        if (!tool@name %in% tool_names) {
          return()
        }
        tool_conf <- agent_conf$tools[[tool@name]]
        tool@annotations$shidashi_type <- "tool"
        tool@annotations$shidashi_enabled <- tool_conf$enabled
        category <- as.character(unlist(tool_conf$category))
        tool@annotations$shidashi_category <- category
        tool@annotations$shidashi_module_id <- module_id
        old_name <- tool@name
        tool@name <- sprintf("tool__%s", tool@name)

        tool_map$set(tool@name, wrap_tools_with_permissions(tool = tool, session = session))
        return()
      })
    })

    # ---- Process skill wrappers (Phase 4) ----
    lapply(names(skill_wrappers), function(sname) {
      wrapper <- skill_wrappers[[sname]]
      skill_tool <- tryCatch(
        wrapper(),
        error = function(e) {
          warning("Failed to create skill tool '", sname, "': ",
                  conditionMessage(e))
          NULL
        }
      )
      if (!inherits(skill_tool, "ellmer::ToolDef")) {
        return()
      }
      skill_conf <- agent_conf$skills[[sname]]
      skill_tool@annotations$shidashi_type <- "skill"
      skill_tool@annotations$shidashi_enabled <- skill_conf$enabled
      skill_tool@annotations$shidashi_category <- c("skill", as.character(skill_conf$category))
      skill_tool@annotations$shidashi_module_id <- module_id
      skill_tool@annotations$shidashi_skill_scripts <- structure(
        as.list(skill_conf$scripts),
        names = vapply(skill_conf$scripts, function(x) {
          x[["name"]]
        }, FUN.VALUE = "")
      )
      skill_tool@name <- sprintf("skill__%s", sname)
      tool_map$set(skill_tool@name, wrap_tools_with_permissions(tool = skill_tool, session = session))
    })

    tool_map

  }

  tool_gen_fun
}


wrap_tools_with_permissions <- function(tool, session) {

  module_id <- tool@annotations$shidashi_module_id
  tool_name <- tool@name

  # tool or skill
  shidashi_type <- tool@annotations$shidashi_type

  # skill, destructive, ...
  shidashi_category <- tool@annotations$shidashi_category

  # permissions
  shidashi_permission <- tool@annotations$shidashi_enabled
  skill_scripts_permission <- as.list(tool@annotations$shidashi_skill_scripts)

  original_fn <- S7::S7_data(tool)

  wrapper_fn <- function(...) {

    agent_mode <- globals_get_agent_mode(module_id = module_id)

    if (identical(agent_mode, "None")) {
      # Agent mode is None
      stop("Agent mode is [None]. All tools & skills are disabled")
    }

    if (is.null(shidashi_permission)) {
      stop("This tool is disabled under current agent permission mode.")
    }

    if (
      !isTRUE(shidashi_permission) &&
        !agent_mode %in% as.character(unlist(shidashi_permission))
    ) {
      stop(
        "This tool is only enabled under the following agent modes: ",
        paste(as.character(unlist(shidashi_permission)), collapse = ", ")
      )
    }

    cl <- match.call()
    arg_exprs <- as.list(cl)[-1L]
    caller <- parent.frame()
    args <- lapply(arg_exprs, eval, envir = caller)

    # Extract and strip _intent before forwarding to original function
    intent <- args[["_intent"]]
    args[["_intent"]] <- NULL

    category <- shidashi_category

    # For skill scripts
    if (length(skill_scripts_permission) > 0 && identical(shidashi_type, "skill") && identical(args$action, "script")) {
      file_name <- args$file_name
      if (length(file_name) == 1 && nzchar(file_name)) {
        script_permission <- as.list(skill_scripts_permission[[file_name]])
        if (
          length(script_permission) > 0 &&
          !isTRUE(script_permission$enabled)
        ) {
          if (isFALSE(script_permission$enabled) ||
              !isTRUE(agent_mode %in% script_permission$enabled)) {
            stop("While skill is permitted, this specific script is disabled under current agent permission mode.")
          }
        }
      }
    }

    # Determine if this specific call is destructive
    needs_confirm <- any(c("destructive", "needs_confirmation") %in% category)

    if (!needs_confirm) {
      return(do.call(original_fn, args))
    }

    # Check confirmation policy
    policy <- globals_get_confirmation_policy(
      module_id = module_id,
      missing = "auto_allow"
    )

    if (identical(policy, "auto_allow")) {
      # Auto-allow: execute without prompting
      return(do.call(original_fn, args))
    }

    if (identical(policy, "auto_reject")) {
      stop(
        "Tool '", tool_name, "' is rejected by policy. ",
        "User needs to change the confirmation policy to 'Auto-allow' ",
        "in the app.",
        call. = FALSE
      )
    }

    # policy == "ask": Ask user for confirmation
    # Extract short tool name (strip type prefix like "tool__" or "skill__")
    short_name <- sub("^(tool|skill)__", "", tool_name)

    confirm_result <- mcp_tool_ask_user(
      arguments = list(
        message = "Do you want to proceed?",
        choices = c("Proceed", "Stop and revise"),
        allow_freeform = FALSE,
        tool_name = short_name,
        intent = if (length(intent) == 1 && nzchar(intent)) intent
      ),
      shiny_session = session
    )
    # mcp_tool_ask_user returns a promise when session is active,
    # or a plain list when session is NULL/closed
    confirm_promise <- if (inherits(confirm_result, "promise")) {
      confirm_result
    } else {
      promises::promise_resolve(confirm_result)
    }

    promises::then(confirm_promise, function(res) {
      user_answer <- res$content[[1]]$text
      if (!identical(user_answer, "Proceed")) {
        stop(
          "User declined destructive action on '", tool_name,
          "'. User response: ", user_answer,
          call. = FALSE
        )
      }
      do.call(original_fn, args)
    })

  }

  # Match formals so ellmer validation stays happy, then inject _intent
  fmls <- formals(original_fn)
  fmls[["_intent"]] <- ""
  formals(wrapper_fn) <- fmls
  S7::S7_data(tool) <- wrapper_fn

  # Inject _intent into the tool's argument schema so the LLM sees it
  tool@arguments@properties[["_intent"]] <- ellmer::type_string(
    "Brief explanation of why you are calling this tool.",
    required = FALSE
  )

  tool
}

#' Create an ellmer::ToolDef for the ask_user built-in
#'
#' Returns a ToolDef that the LLM can invoke to ask the user a question.
#' Uses the browser modal when a Shiny session is available, falls back
#' to the R console when \code{interactive()}, or rejects.
#' @param shiny_session The Shiny session (or \code{NULL})
#' @return An \code{ellmer::ToolDef}
#' @keywords internal
#' @noRd
make_ask_user_tool <- function(shiny_session) {
  ellmer::tool(
    fun = function(message, choices = NULL, allow_freeform = TRUE) {
      result <- mcp_tool_ask_user(
        arguments = list(
          message = message,
          choices = choices,
          allow_freeform = allow_freeform
        ),
        shiny_session = shiny_session
      )
      if (promises::is.promise(result)) {
        promises::then(result, function(res) res$content[[1L]]$text)
      } else {
        result$content[[1L]]$text
      }
    },
    name = "ask_user",
    description = paste(
      "Ask the user a question via a modal dialog (when a Shiny",
      "session is available) or the R console. Use this when you",
      "need the user to make a choice, confirm an action, or",
      "provide free-form input. Returns the user's response text."
    ),
    arguments = list(
      message = ellmer::type_string(
        "The question or message to show the user."
      ),
      choices = ellmer::type_array(
        "Optional predefined choices shown as buttons (e.g. ['Yes', 'No']).",
        items = ellmer::type_string(),
        required = FALSE
      ),
      allow_freeform = ellmer::type_boolean(
        "Whether to show a free-form text area in addition to choices. Default TRUE.",
        required = FALSE
      )
    )
  )
}


