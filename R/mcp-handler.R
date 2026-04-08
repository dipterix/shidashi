# ---- MCP (Model Context Protocol) JSON-RPC 2.0 handler for shidashi ----
#
# This module implements a Streamable HTTP MCP endpoint that lives inside
# the same httpuv process as the Shiny app.  No sidecar process needed.
#
# Entry point: `mcp_http_handler(req)` is called from `mcp_app_handler()`
# when `req$PATH_INFO == "/mcp"` and `req$REQUEST_METHOD == "POST"`.
#
# Phase 3: Dynamic per-session tools with stateful MCP↔Shiny binding.
#
# Session registry: session$token -> entry
# Entry structure:
#   list(
#     shiny_session      = <ShinySession>,
#     shidashi_module_id = <string or NULL>,
#     mcp_session_ids    = c(<array of MCP session IDs>)
#     namespace          = "",
#     url                = "",
#     registered_at      = <POSIXct>,
#     tools              = <named list of ToolDef objects or NULL>
#   )

# ---------- MCP-specific session binding helpers --------------------------
# Generic helpers (register_session, unregister_session, sweep_closed_sessions,
# get_session_entry) are in globals.R.

# Given a MCP session ID, find shiny session tokens
mcp_tool_bound_shinysessions <- function(mcp_session_id) {
  if (length(mcp_session_id) != 1 || is.na(mcp_session_id) || !nzchar(mcp_session_id)) {
    return(character(0L))
  }
  registry <- globals_session_registry()
  tokens <- registry$keys()
  tokens[
    vapply(tokens, function(token) {
      entry <- registry$get(token)
      isTRUE(mcp_session_id %in% entry$mcp_session_ids)
    }, FUN.VALUE = FALSE)
  ]
}

# Given a MCP session ID, unregister the mcp session from shiny sessions
mcp_tool_unregister_shinysession <- function(mcp_session_id) {
  tokens <- mcp_tool_bound_shinysessions(mcp_session_id)
  if (!length(tokens)) { return() }

  registry <- globals_session_registry()
  lapply(tokens, function(token) {
    entry <- registry$get(token)
    entry$mcp_session_ids <- entry$mcp_session_ids[!entry$mcp_session_ids %in% mcp_session_id]
    registry$set(token, entry)
  })

  invisible(TRUE)
}

# ---------- app-level HTTP handler ----------------------------------------

# Create an HTTP handler for the MCP endpoint
register_mcp_route <- function(app) {
  default_handlers <- app$httpHandler
  mcp_handler <- function(req) {
    if (!identical(req$PATH_INFO, "/mcp")) return(NULL)
    if (identical(req$REQUEST_METHOD, "POST")) {
      return(mcp_http_handler(req))
    }
    if (identical(req$REQUEST_METHOD, "DELETE")) {
      # Clean up MCP session binding on teardown
      sid <- req$HTTP_MCP_SESSION_ID
      mcp_tool_unregister_shinysession(sid)
      return(shiny::httpResponse(200L, "application/json", "{}"))
    }
    if (identical(req$REQUEST_METHOD, "GET")) {
      # Informational response for browser / debugging
      info <- jsonlite::toJSON(
        list(
          status  = "ok",
          message = "shidashi MCP endpoint active. Use POST with JSON-RPC 2.0 to interact."
        ),
        auto_unbox = TRUE, null = "null"
      )
      return(shiny::httpResponse(200L, "application/json", info))
    }
    # Other methods
    shiny::httpResponse(405L, "", "")
  }

  app$httpHandler <- function(req) {
    response <- mcp_handler(req)
    if (!is.null(response)) {
      return(response)
    }
    return(default_handlers(req))
  }

  # Exclude /mcp from httpuv static-path handling so POST/DELETE
  # requests reach the R handler instead of being rejected with 400.
  app$staticPaths <- c(app$staticPaths, list(mcp = httpuv::excludeStaticPath()))

  return(app)
}

# ---------- public entry point -------------------------------------------

#' Handle an incoming MCP HTTP request
#'
#' Called from \code{adminlte_ui()} when \code{req$PATH_INFO == "/mcp"}.
#' Reads the JSON-RPC 2.0 body, dispatches to the appropriate handler,
#' and returns a \code{shiny::httpResponse()}.
#'
#' @param req The Rook request environment
#' @return A \code{shiny::httpResponse} object
#' @noRd
mcp_http_handler <- function(req) {

  # --- sweep stale Shiny sessions (defensive) ---------------------------
  sweep_closed_sessions()

  # --- read body --------------------------------------------------------
  mcp_session_id <- req$HTTP_MCP_SESSION_ID  # may be NULL on initialize
  body_raw <- tryCatch(
    req$rook.input$read(),
    error = function(e) raw(0)
  )
  if (length(body_raw) == 0L) {
    return(mcp_json_error(
      id = NULL,
      code = -32700L,
      message = "Parse error: empty body",
      mcp_session_id = mcp_session_id
    ))
  }

  body_text <- rawToChar(body_raw)
  msg <- tryCatch(
    jsonlite::fromJSON(body_text, simplifyVector = TRUE,
                       simplifyDataFrame = FALSE,
                       simplifyMatrix = FALSE),
    error = function(e) NULL
  )
  if (is.null(msg)) {
    return(mcp_json_error(
      id = NULL,
      code = -32700L,
      message = "Parse error: invalid JSON",
      mcp_session_id = mcp_session_id
    ))
  }

  # --- validate JSON-RPC envelope ---------------------------------------
  jsonrpc <- msg$jsonrpc
  method  <- msg$method
  id      <- msg$id
  params  <- msg$params

  # TODO: what if this is a parallel call?
  if (!identical(jsonrpc, "2.0") || !is.character(method) ||
      length(method) != 1L) {
    return(mcp_json_error(
      id = id,
      code = -32600L,
      message = "Invalid Request: missing jsonrpc or method",
      mcp_session_id = mcp_session_id
    ))
  }

  # --- notifications (no `id`) => 202 Accepted --------------------------
  is_notification <- is.null(id)

  if (is_notification) {
    # notifications/initialized is the only one we expect in Phase 1
    # TODO: should we notify in shiny?
    return(shiny::httpResponse(
      status = 202L,
      content_type = "",
      content = ""
    ))
  }

  # --- dispatch ----------------------------------------------------------


  result <- tryCatch(
    switch(
      method,
      "initialize"  = mcp_handle_initialize(id, params),
      "tools/list"  = mcp_handle_tools_list(id, params, mcp_session_id),
      "tools/call"  = mcp_handle_tools_call(id, params, mcp_session_id),
      "ping"        = mcp_handle_ping(id, mcp_session_id),
      # "resources/list" = mcp_handle_resources_list(id, params, mcp_session_id),
      # "resources/read" = mcp_...,
      # default: method not found
      mcp_json_error(
        id = id,
        code = -32601L,
        message = paste0("Method not found: ", method),
        mcp_session_id = mcp_session_id
      )
    ),
    error = function(e) {
      mcp_json_error(
        id = id,
        code = -32603L,
        message = paste0("Internal error: ", conditionMessage(e)),
        mcp_session_id = mcp_session_id
      )
    }
  )

  result
}

# ---------- method handlers ----------------------------------------------

#' Handle MCP `initialize` request
#' @keywords internal
#' @noRd
mcp_handle_initialize <- function(id, params) {

  # Generate a unique MCP session ID
  mcp_session_id <- digest::digest(
    list(Sys.time(), rand_string(), id, params,
         Sys.getpid(), sample.int(.Machine$integer.max, 1L)),
    algo = "sha256"
  )

  pkg_version <- tryCatch(
    as.character(utils::packageVersion("shidashi")),
    error = function(e) "0.0.0"
  )

  body <- jsonlite::toJSON(
    list(
      jsonrpc = "2.0",
      id      = id,
      result  = list(
        protocolVersion = "2025-03-26",
        capabilities    = list(
          tools   = list(listChanged = TRUE)
        ),
        serverInfo      = list(
          name    = "shidashi",
          version = pkg_version
        )
      )
    ),
    auto_unbox = TRUE,
    null = "null"
  )

  shiny::httpResponse(
    status       = 200L,
    content_type = "application/json",
    content      = body,
    headers      = list(`Mcp-Session-Id` = mcp_session_id)
  )
}

#' Handle MCP `ping` request
#' @keywords internal
#' @noRd
mcp_handle_ping <- function(id, mcp_session_id = NULL) {
  mcp_json_result(id, structure(list(), names = character(0L)), mcp_session_id)
}

# Pre-list shared tool & skill schemas (available before session binding).
# Reads agents/tool-schema.yaml (for tools), discovers skills from
# agents/skills/ via skill_wrapper(), and injects builtin shiny_* tools.
# No caching — always re-reads so changes are picked up immediately.
mcp_prelisted_tool_schemas <- function() {

  schemas <- list()

  # ---- Builtin shiny_* tool schemas (always available) ----
  schemas[["tool__shiny_input_info"]] <- list(
    name        = "tool__shiny_input_info",
    description = paste(
      "Query registered shiny input specifications.",
      "Returns input IDs, descriptions, types, update functions,",
      "whether each is writable, and (when a session is active)",
      "whether each currently exists and its current value."
    ),
    inputSchema = list(
      type       = "object",
      properties = list(
        inputIds = list(
          type        = "array",
          items       = list(type = "string", description = "Shiny input ID"),
          description = "Optional: specific input IDs to query. Omit to list all registered inputs."
        )
      )
    )
  )

  schemas[["tool__shiny_input_update"]] <- list(
    name        = "tool__shiny_input_update",
    description = paste(
      "Update a shiny input value by its ID.",
      "The value will be sent to the corresponding shiny update function",
      "(e.g. updateTextInput, updateSelectInput, updateNumericInput).",
      "Call `tool__shiny_input_info` first to discover available input IDs,",
      "their types, current values, and whether they are writable."
    ),
    inputSchema = list(
      type       = "object",
      properties = list(
        inputId = list(
          type        = "string",
          description = "Shiny input ID of which the value is to be changed"
        ),
        value = list(
          type        = "string",
          description = "The new value for the input. Use JSON encoding for non-string values (e.g. 123, [1,2,3], {\"a\":1})."
        )
      ),
      required = list("inputId")
    )
  )

  schemas[["tool__shiny_query_ui"]] <- list(
    name        = "tool__shiny_query_ui",
    description = paste(
      "Request the HTML content of a UI element by CSS selector.",
      "This sends a query to the browser and returns a request_id.",
      "The browser response is asynchronous; call `tool__shiny_query_ui_result`",
      "with the returned request_id to retrieve the actual content.",
      "Wait briefly (1-2 seconds) before fetching the result."
    ),
    inputSchema = list(
      type       = "object",
      properties = list(
        css_selector = list(
          type        = "string",
          description = "A CSS selector to query (e.g. '#my_output', '.card-body', 'div[data-id=\"plot\"]')."
        )
      ),
      required = list("css_selector")
    )
  )

  schemas[["tool__shiny_query_ui_result"]] <- list(
    name        = "tool__shiny_query_ui_result",
    description = paste(
      "Fetch the result of a previous `tool__shiny_query_ui` request.",
      "Returns the innerHTML of the matched element, or an inline image",
      "if the element is a canvas or contains only an <img> tag.",
      "If the result is not yet available and the request has not timed out,",
      "wait a moment and try again."
    ),
    inputSchema = list(
      type       = "object",
      properties = list(
        request_id = list(
          type        = "string",
          description = "The request_id returned by a prior `tool__shiny_query_ui` call."
        )
      ),
      required = list("request_id")
    )
  )

  schemas[["tool__shiny_output_info"]] <- list(
    name        = "tool__shiny_output_info",
    description = paste(
      "List registered Shiny output elements and optionally retrieve",
      "their rendered HTML content. When outputIds is omitted, returns",
      "all registered outputs with their descriptions. You can get the",
      "HTML content of output via `tool__shiny_query_ui(selector)`"
    ),
    inputSchema = list(
      type       = "object",
      properties = list(
        outputIds = list(
          type        = "array",
          items       = list(type = "string", description = "Shiny output ID"),
          description = "Optional: specific output IDs to query. Omit to list all registered outputs."
        )
      )
    )
  )

  # ---- tool-schema.yaml: user-defined pre-listed tool schemas ----
  root_path <- tryCatch(template_root(), error = function(e) NULL)
  if (!is.null(root_path) && dir.exists(root_path)) {

    schema_path <- file.path(root_path, "agents", "tool-schema.yaml")
    if (file.exists(schema_path)) {
      tool_schema_conf <- tryCatch(
        yaml::read_yaml(schema_path),
        error = function(e) NULL
      )
      if (is.list(tool_schema_conf$tools)) {
        for (ts in tool_schema_conf$tools) {
          if (!length(ts$name) || !nzchar(ts$name)) next
          full_name <- sprintf("tool__%s", ts$name)
          schemas[[full_name]] <- list(
            name        = full_name,
            description = ts$description %||% "",
            inputSchema = ts$inputSchema %||% list(
              type = "object",
              properties = structure(list(), names = character(0))
            )
          )
        }
      }
    }

    # ---- Skill schemas: auto-discovered from agents/skills/ ----
    skills_dir <- file.path(root_path, "agents", "skills")
    if (dir.exists(skills_dir)) {
      skill_dirs <- list.dirs(skills_dir, recursive = FALSE, full.names = TRUE)
      for (sdir in skill_dirs) {
        sname <- basename(sdir)
        if (!file.exists(file.path(sdir, "SKILL.md"))) next
        skill_tool <- tryCatch({
          wrapper <- skill_wrapper(sdir)
          wrapper()
        }, error = function(e) NULL)
        if (!inherits(skill_tool, "ellmer::ToolDef")) next
        skill_tool@name <- sprintf("skill__%s", sname)
        schemas[[skill_tool@name]] <- ellmer_tool_schema(skill_tool)
      }
    }
  }

  schemas
}

#' Handle MCP `tools/list` request
#' @keywords internal
#' @noRd
mcp_handle_tools_list <- function(id, params, mcp_session_id) {

  # Built-in tools (always available)
  tools <- list(
    list(
      name        = "list_shinysessions",
      description = "List all active Shiny sessions. Each session represents a browser tab or iframe. Returns token, module_id, available tool names, and registration time. Call this first to find a session to bind to, then call `register_shinysession` to bind the session.", # nolint: line_length_linter.
      inputSchema = list(
        type       = "object",
        properties = structure(list(), names = character(0))
      )
    ),
    list(
      name        = "register_shinysession",
      description = "Bind this MCP session to a Shiny session by token. After binding, per-session tools become available. Call `list_shinysessions` first to obtain the list of available shiny session token. You can switch sessions by calling this again with a different token.", # nolint: line_length_linter.
      inputSchema = list(
        type       = "object",
        properties = list(
          token = list(
            type        = "string",
            description = "The Shiny session token from list_shinysessions"
          )
        ),
        required = list("token")
      )
    ),
    list(
      name        = "get_session_info",
      description = "Show the current MCP-to-Shiny binding status: bound token, module_id, and available tools with their descriptions.", # nolint: line_length_linter.
      inputSchema = list(
        type       = "object",
        properties = structure(list(), names = character(0))
      )
    )
  )

  # Collect names of bound-session tools for deduplication
  bound_tool_names <- character(0)

  # If bound to a Shiny session, add per-session tools
  bound_token <- mcp_tool_bound_shinysessions(mcp_session_id = mcp_session_id)
  if (length(bound_token)) {
    # Only use the first session: can only bind one at a time
    bound_token <- bound_token[[1]]
    entry <- get_session_entry(bound_token)
    if (length(entry) && entry$tools$size() > 0) {
      # Filter tools by current agent mode
      module_id <- entry$namespace
      current_mode <- globals_get_agent_mode(module_id = module_id)
      enabled_tools <- Filter(function(t) {
        is_tool_enabled_for_mode(t, current_mode)
      }, entry$tools$as_list())
      if (length(enabled_tools)) {
        schema <- lapply(enabled_tools, ellmer_tool_schema)
        tools <- c(tools, unname(schema))
        bound_tool_names <- vapply(schema, `[[`, "name",
                                   FUN.VALUE = character(1))
      }
    }
  }

  # Pre-listed tools & skills (visible even without a bound session).
  # When a session IS bound, skip any pre-listed schema whose name
  # already appeared in bound-session tools (live version wins).
  prelisted <- mcp_prelisted_tool_schemas()
  if (length(prelisted)) {
    for (pschema in prelisted) {
      if (!pschema$name %in% bound_tool_names) {
        tools <- c(tools, list(pschema))
      }
    }
  }

  # ask_user built-in (always available; adapts to Shiny / console / reject)
  tools <- c(tools, list(list(
    name        = "ask_user",
    description = paste(
      "Ask the user a question via a modal dialog (when a Shiny",
      "session is bound) or the R console. Use this when you need",
      "the user to make a choice, confirm an action, or provide",
      "free-form input. Returns the user's response or indicates",
      "cancellation."
    ),
    inputSchema = list(
      type       = "object",
      properties = list(
        message = list(
          type        = "string",
          description = "The question or message to show the user."
        ),
        choices = list(
          type        = "array",
          items       = list(type = "string"),
          description = "Optional predefined choices as buttons (e.g. ['Yes', 'No'])."
        ),
        allow_freeform = list(
          type        = "boolean",
          description = "Whether to show a text area for free-form input. Default: true."
        )
      ),
      required = list("message")
    )
  )))

  mcp_json_result(id, list(tools = tools), mcp_session_id)
}


#' Handle MCP `tools/call` request
#' @keywords internal
#' @noRd
mcp_handle_tools_call <- function(id, params, mcp_session_id) {

  tool_name <- params$name
  arguments <- params$arguments

  if (!is.character(tool_name) || length(tool_name) != 1L) {
    return(mcp_json_error(
      id = id,
      code = -32602L,
      message = "Invalid params: missing or invalid tool name",
      mcp_session_id = mcp_session_id
    ))
  }

  # ---- built-in tools (always available) --------------------------------
  result <- switch(
    tool_name,
    "list_shinysessions" = mcp_tool_list_shinysessions(arguments),
    "register_shinysession" = mcp_tool_register_shinysession(
      arguments, mcp_session_id),
    "get_session_info" = mcp_tool_get_session_info(mcp_session_id),
    "ask_user" = {
      # In MCP mode (Mode 2), asking users via browser modals doesn't work
      # because users are interacting in VSCode/IDE, not in the browser.
      # Return an MCP error instructing the AI to ask questions in its own chat.
      list(
        content = list(list(
          type = "text",
          text = paste0(
            "The ask_user tool is not available in MCP mode. ",
            "Please ask the user directly in your chat interface instead."
          )
        )),
        isError = TRUE
      )
    },
    NULL # not a built-in
  )

  if (!is.null(result)) {
    # After a successful register_shinysession, the tool list changes;
    # notify the client via SSE so it refreshes its tool catalogue.
    if (identical(tool_name, "register_shinysession") &&
        isFALSE(result$isError)) {
      return(mcp_json_result(
        id, result, mcp_session_id,
        content_type  = "text/event-stream",
        notifications = list(
          list(jsonrpc = "2.0", method = "notifications/tools/list_changed")
        )
      ))
    }
    return(mcp_json_result(id, result, mcp_session_id))
  }

  # ---- per-session tools (require binding) ------------------------------
  bound_token <- mcp_tool_bound_shinysessions(mcp_session_id = mcp_session_id)
  if (!length(bound_token)) {
    result <- list(
      content = list(list(
        type = "text",
        text = paste0(
          "No Shiny session bound, or the session has been ended/closed. ",
          "Call `list_shinysessions` first to list available sessions, and ",
          "then `register_shinysession` to bind to a shiny session. ",
          "To un-register or re-register, call this tool again with other ",
          "tokens."
        )
      )),
      isError = TRUE
    )
    return(mcp_json_result(id, result, mcp_session_id))
  }

  bound_token <- bound_token[[1]]
  entry <- get_session_entry(bound_token)

  if (is.null(entry)) {
    result <- list(
      content = list(list(
        type = "text",
        text = "Bound Shiny session has ended/closed. Call `list_shinysessions` first to list available sessions, and then `register_shinysession` to bind to a shiny session"
      )),
      isError = TRUE
    )
    return(mcp_json_result(id, result, mcp_session_id))
  }

  # Look up tool in session's registered tools
  tool_obj <- entry$tools$get(tool_name, missing = NULL)

  if (is.null(tool_obj)) {
    result <- list(
      content = list(list(
        type = "text",
        text = paste0(
          "Tool '", tool_name, "' not found on bound session. ",
          "Available tools: ", paste(entry$tools$keys(), collapse = ", ")
        )
      )),
      isError = TRUE
    )
    return(mcp_json_result(id, result, mcp_session_id))
  }

  # ---- Mode guard: reject if mode is "None" ----
  current_mode <- globals_get_agent_mode(module_id = entry$namespace)
  if (identical(current_mode, "None")) {
    result <- list(
      content = list(list(
        type = "text",
        text = paste0(
          "Agent mode is 'None'. All tools & skills are disabled. ",
          "Change the mode in the dashboard to enable tool calls."
        )
      )),
      isError = TRUE
    )
    return(mcp_json_result(id, result, mcp_session_id))
  }

  # ---- Mode guard: reject if tool is not enabled for current mode ----
  if (!is_tool_enabled_for_mode(tool_obj, current_mode)) {
    result <- list(
      content = list(list(
        type = "text",
        text = paste0(
          "Tool '", tool_name, "' is not enabled for mode '",
          current_mode %||% "(none)", "'. ",
          "Switch to an appropriate mode before calling this tool."
        )
      )),
      isError = TRUE
    )
    return(mcp_json_result(id, result, mcp_session_id))
  }

  # ---- Skill script mode guard: per-script overrides ----
  skill_scripts <- tool_obj@annotations$shidashi_skill_scripts
  if (length(skill_scripts) && identical(arguments$action, "script") &&
      length(arguments$file_name) && nzchar(arguments$file_name)) {
    if (!is_script_enabled_for_mode(skill_scripts, arguments$file_name,
                                    current_mode)) {
      result <- list(
        content = list(list(
          type = "text",
          text = paste0(
            "Script '", arguments$file_name, "' in skill '", tool_name,
            "' is not enabled for mode '", current_mode %||% "(none)", "'."
          )
        )),
        isError = TRUE
      )
      return(mcp_json_result(id, result, mcp_session_id))
    }
  }

  # ---- Destructive/needs_confirmation category guard ----
  tool_category <- tool_obj@annotations$shidashi_category
  needs_confirm <- is.character(tool_category) &&
    any(c("destructive", "needs_confirmation") %in% tool_category)

  # Also check per-script category for skills
  if (!needs_confirm && length(skill_scripts) &&
      identical(arguments$action, "script") &&
      length(arguments$file_name) && nzchar(arguments$file_name)) {
    script_cat <- get_script_category(skill_scripts, arguments$file_name)
    needs_confirm <- any(c("destructive", "needs_confirmation") %in% script_cat)
  }

  if (needs_confirm) {
    # Check confirmation policy
    policy <- globals_get_confirmation_policy(
      module_id = entry$namespace, missing = "auto_allow"
    )

    if (identical(policy, "auto_reject")) {
      result <- list(
        content = list(list(
          type = "text",
          text = paste0(
            "Tool '", tool_name, "' requires confirmation but policy is set to 'Auto-reject'. ",
            "Change the confirmation policy in the dashboard to 'Auto-allow' to enable."
          )
        )),
        isError = TRUE
      )
      return(mcp_json_result(id, result, mcp_session_id))
    }

    if (identical(policy, "ask")) {
      # In MCP mode (Mode 2), we can't show browser modals for confirmation.
      # Auto-reject and instruct user to change policy if they want to allow.
      result <- list(
        content = list(list(
          type = "text",
          text = paste0(
            "Tool '", tool_name, "' requires confirmation. ",
            "In MCP mode, interactive confirmation is not available. ",
            "Change the confirmation policy in the dashboard to 'Auto-allow' to enable this tool."
          )
        )),
        isError = TRUE
      )
      return(mcp_json_result(id, result, mcp_session_id))
    }
    # policy == "auto_allow": proceed without confirmation
  }

  # Call the ToolDef with the provided arguments
  provider <- get_mcp_provider()
  result <- ellmer_tool_call(tool_obj, arguments, provider = provider)

  # Handle async tool results (promises)
  if (promises::is.promise(result)) {
    return(promises::then(result, function(res) {
      mcp_json_result(id, res, mcp_session_id)
    }))
  }

  mcp_json_result(id, result, mcp_session_id)
}

# ---------- built-in tool implementations ----------------------------------

#' List active Shiny sessions (enhanced with module_id and tool names)
#' @keywords internal
#' @noRd
mcp_tool_list_shinysessions <- function(arguments) {
  registry <- globals_session_registry()
  tokens <- registry$keys()

  sessions_info <- lapply(tokens, function(tk) {
    entry <- registry$get(tk)
    if (is.null(entry) || is.null(entry$shiny_session)) return(NULL)
    closed <- tryCatch(entry$shiny_session$isClosed(), error = function(e) TRUE)
    if (isTRUE(closed)) return(NULL)

    tool_names <- character(0)
    if (entry$tools$size() > 0L) {
      tool_names <- entry$tools$keys()
    }

    list(
      token         = tk,
      module_id     = entry$shidashi_module_id %||% "",
      namespace     = entry$namespace,
      # url           = entry$url,
      tool_names    = tool_names,
      registered_at = format(entry$registered_at, "%Y-%m-%dT%H:%M:%S")
    )
  })
  sessions_info <- Filter(Negate(is.null), sessions_info)

  text <- as.character(
    jsonlite::toJSON(unname(as.list(sessions_info)),
                     auto_unbox = TRUE, null = "null")
  )
  list(
    content = list(list(type = "text", text = text)),
    isError = FALSE
  )
}

#' Bind MCP session to a Shiny session
#' @keywords internal
#' @noRd
mcp_tool_register_shinysession <- function(arguments, mcp_session_id) {

  if (missing(mcp_session_id) || length(mcp_session_id) != 1 ||
      is.na(mcp_session_id) || !is.character(mcp_session_id) ||
      !nzchar(mcp_session_id)) {
    return(list(
      content = list(list(
        type = "text",
        text = "Error: No mcp_session_id. Call initialize first."
      )),
      isError = TRUE
    ))
  }

  token <- arguments$token
  if (!is.character(token) || length(token) != 1L || !nzchar(token)) {
    return(list(
      content = list(list(
        type = "text",
        text = "Error: 'token' (string) is required. Call `list_shinysessions` to obtain a valid token."
      )),
      isError = TRUE
    ))
  }


  # Validate Shiny session exists and is open
  entry <- get_session_entry(token)

  # Unregister existing sessions
  mcp_tool_unregister_shinysession(mcp_session_id = mcp_session_id)

  if (is.null(entry)) {
    return(list(
      content = list(list(
        type = "text",
        text = paste0(
          "Error: No active session for token '", token,
          "'. Call list_shinysessions to list available session tokens. ",
          "In addition, your previous sessions have been unregistered."
        )
      )),
      isError = TRUE
    ))
  }

  # re-fetch
  entry <- get_session_entry(token)

  # Bind MCP session to Shiny token
  entry$mcp_session_ids <- unique(c(entry$mcp_session_ids, mcp_session_id))
  registry <- globals_session_registry()
  registry$set(token, entry)

  # Build response with info about the bound session
  tool_info <- lapply(entry$tools$as_list(), function(tool_obj) {
    if (!inherits(tool_obj, "ellmer::ToolDef")) { return() }
    list(name = tool_obj@name,
         description = paste(tool_obj@description, collapse = "\n"))
  })
  tool_info <- drop_null(tool_info)

  info <- list(
    status    = "bound",
    token     = token,
    module_id = entry$shidashi_module_id %||% "",
    tools     = unname(as.list(tool_info))
  )

  # Build a message that explicitly tells the AI the tools are callable
  tool_names <- vapply(tool_info, `[[`, "name", FUN.VALUE = character(1L))
  if (length(tool_names)) {
    msg <- paste0(
      "Successfully bound to Shiny session '", token, "'.",
      " Please NOW search for MCP tools before invoking deferred tools.",
      # " The following tools will be available: ",
      # paste(tool_names, collapse = ", "), ".",
      " * Call `tools/list` (e.g. tool_search_tool_regex) to see their ",
      "full schemas. You MUST search the tools again to enable ",
      "the new deferred tools."
    )
  } else {
    msg <- paste0(
      "Successfully bound to Shiny session '", token, "'.",
      " No per-session tools are registered on this session."
    )
  }

  # detail <- as.character(jsonlite::toJSON(info, auto_unbox = TRUE, null = "null"))
  # text <- paste0(msg, "\n\nDetails:\n", detail)
  text <- msg
  list(
    content = list(list(type = "text", text = text)),
    isError = FALSE
  )
}

#' Show current MCP session binding status
#' @keywords internal
#' @noRd
mcp_tool_get_session_info <- function(mcp_session_id) {
  if (
    missing(mcp_session_id) ||
      length(mcp_session_id) != 1 ||
      is.na(mcp_session_id) ||
      !is.character(mcp_session_id) ||
      !nzchar(mcp_session_id)
  ) {
    return(list(
      content = list(list(
        type = "text",
        text = as.character(jsonlite::toJSON(
          list(status = "no_mcp_session", message = "Missing mcp_session_id. Call initialize first."),
          auto_unbox = TRUE,
          null = "null"
        ))
      )),
      isError = FALSE
    ))
  }

  bound_token <- mcp_tool_bound_shinysessions(mcp_session_id)
  if (!length(bound_token)) {
    return(list(
      content = list(list(
        type = "text",
        text = as.character(jsonlite::toJSON(
          list(status = "unbound",
               message = "Not bound to any active Shiny session or session is ended. Call register_shinysession to bind one."),
          auto_unbox = TRUE, null = "null"
        ))
      )),
      isError = FALSE
    ))
  }

  entry <- get_session_entry(bound_token)
  if (is.null(entry)) {
    return(list(
      content = list(list(
        type = "text",
        text = as.character(jsonlite::toJSON(
          list(status = "session_closed",
               message = "Bound session has closed. Call register_shinysession with a new token."),
          auto_unbox = TRUE, null = "null"
        ))
      )),
      isError = FALSE
    ))
  }

  tool_info <- lapply(entry$tools$as_list(), function(tool_obj) {
    if (!inherits(tool_obj, "ellmer::ToolDef")) { return() }
    list(name = tool_obj@name,
         description = paste(tool_obj@description, collapse = "\n"))
  })
  tool_info <- drop_null(tool_info)

  info <- list(
    status    = "bound",
    token     = bound_token,
    module_id = entry$shidashi_module_id %||% "",
    # url       = entry$url,
    tools     = unname(as.list(tool_info)) # array of objects
  )

  text <- as.character(jsonlite::toJSON(info, auto_unbox = TRUE, null = "null"))
  list(
    content = list(list(type = "text", text = text)),
    isError = FALSE
  )
}


#' Ask the user a question
#'
#' Tries three strategies in order:
#' \enumerate{
#'   \item If a live Shiny session is provided, ask via a browser modal.
#'   \item If \code{interactive()}, ask via the R console.
#'   \item Otherwise reject with an error.
#' }
#' @param arguments list with \code{message}, optional \code{choices},
#'   optional \code{allow_freeform}.
#' @param shiny_session A Shiny session or \code{NULL}.
#' @return A \code{promises::promise} (Shiny path) or a plain list with
#'   \code{content} and \code{isError}.
#' @keywords internal
#' @noRd
mcp_tool_ask_user <- function(arguments, shiny_session = NULL) {

  message_text <- arguments$message
  if (!is.character(message_text) || !nzchar(message_text)) {
    return(list(
      content = list(list(
        type = "text",
        text = "Invalid params: 'message' is required."
      )),
      isError = TRUE
    ))
  }

  choices <- as.character(unlist(arguments$choices))
  allow_freeform <- !identical(arguments$allow_freeform, FALSE)

  # --- Strategy 1: Shiny browser modal -----------------------------------
  session_ok <- !is.null(shiny_session) &&
    is.environment(shiny_session) &&
    !isTRUE(tryCatch(shiny_session$isClosed(), error = function(e) TRUE))

  if (session_ok) {
    return(mcp_tool_ask_user_shiny(
      message_text, choices, allow_freeform, shiny_session,
      tool_name = arguments$tool_name,
      intent = arguments$intent
    ))
  }

  # --- Strategy 2: interactive R console ---------------------------------
  if (interactive()) {
    return(mcp_tool_ask_user_console(
      message_text, choices, allow_freeform
    ))
  }

  # --- Strategy 3: reject ------------------------------------------------
  list(
    content = list(list(
      type = "text",
      text = "Cannot ask user: no Shiny session available and R is not interactive."
    )),
    isError = TRUE
  )
}

# Ask user via Shiny browser modal (returns a promise)
mcp_tool_ask_user_shiny <- function(message_text, choices, allow_freeform,
                                    shiny_session,
                                    tool_name = NULL, intent = NULL) {
  request_id <- rand_string(prefix = "ask_user_")
  input_id <- shiny_session$ns("@shidashi_ask_user_result@")

  payload <- list(
    request_id = request_id,
    input_id = input_id,
    message = message_text,
    choices = choices,
    allow_freeform = allow_freeform
  )
  if (length(tool_name) == 1 && nzchar(tool_name)) {
    payload$tool_name <- tool_name
  }
  if (length(intent) == 1 && nzchar(intent)) {
    payload$intent <- intent
  }
  shiny_session$sendCustomMessage("shidashi.ask_user", payload)

  check_fn <- coro::async(function() {
    remaining <- 120L  # 120 x 500ms = 60 seconds timeout

    while (remaining >= 0) {
      remaining <- remaining - 1L
      res <- shiny::isolate(
        shiny_session$input[["@shidashi_ask_user_result@"]]
      )
      if (!is.null(res) && identical(res$request_id, request_id)) {
        if (isTRUE(res$cancelled)) {
          return(list(
            content = list(list(type = "text",
                                text = "User cancelled the request.")),
            isError = FALSE
          ))
        } else {
          return(list(
            content = list(list(type = "text",
                                text = res$value %||% "")),
            isError = FALSE
          ))
        }
      } else {
        coro::async_sleep(0.5)
      }
    }

    return(list(
      content = list(list(type = "text",
                          text = "Timeout: no response from user within 60 seconds.")),
      isError = FALSE
    ))

  })
  check_fn()
}

# Ask user via the R console (synchronous, returns a plain list)
mcp_tool_ask_user_console <- function(message_text, choices, allow_freeform) {
  cat("\n", message_text, "\n", sep = "")
  answer <- NULL

  if (length(choices)) {
    sel <- utils::menu(choices, title = "Select an option:")
    if (sel == 0L) {
      return(list(
        content = list(list(type = "text",
                           text = "User cancelled the request.")),
        isError = FALSE
      ))
    }
    answer <- choices[[sel]]
  }

  if (allow_freeform) {
    prompt <- if (is.null(answer)) "Your response: " else "Additional input (or Enter to skip): "
    freeform <- readline(prompt)
    if (nzchar(freeform)) {
      answer <- if (is.null(answer)) freeform else paste0(answer, "\n", freeform)
    }
  }

  if (is.null(answer) || !nzchar(answer)) {
    answer <- "(no response)"
  }

  list(
    content = list(list(type = "text", text = answer)),
    isError = FALSE
  )
}

# ---------- internal helpers ----------------------------------------------

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

  dummy_provider <- ellmer::Provider(name = "dummy",
                                     model = "dummy",
                                     base_url = "https://dummy")
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

# ---------- JSON helpers -------------------------------------------------

#' Build a JSON-RPC 2.0 error response
#' @keywords internal
#' @noRd
mcp_json_error <- function(id, code, message, mcp_session_id = NULL) {

  headers <- list()
  if (length(mcp_session_id) == 1 && nzchar(mcp_session_id)) {
    headers[["Mcp-Session-Id"]] <- mcp_session_id
  }

  body <- jsonlite::toJSON(
    list(
      jsonrpc = "2.0",
      id      = id,
      error   = list(
        code    = code,
        message = message
      )
    ),
    auto_unbox = TRUE,
    null = "null"
  )

  shiny::httpResponse(
    status       = 200L,
    content_type = "application/json",
    content      = body,
    headers      = headers
  )
}


#' Build a JSON-RPC 2.0 success response
#'
#' @param id JSON-RPC request id.
#' @param result The result payload (list).
#' @param mcp_session_id Optional MCP session ID for the response header.
#' @param content_type Either \code{"application/json"} (default) or
#'   \code{"text/event-stream"}.  When SSE, each JSON-RPC message is
#'   emitted as an \code{event: message} frame.
#' @param notifications A list of additional JSON-RPC notification objects
#'   (each a named list with \code{jsonrpc}, \code{method}, and optionally
#'   \code{params}) to append after the result.  Only used when
#'   \code{content_type} is \code{"text/event-stream"}.
#' @keywords internal
#' @noRd
mcp_json_result <- function(id, result, mcp_session_id = NULL,
                            content_type = c("application/json",
                                             "text/event-stream"),
                            notifications = NULL) {
  content_type <- match.arg(content_type)
  headers <- list()
  if (length(mcp_session_id) == 1 && nzchar(mcp_session_id)) {
    headers[["Mcp-Session-Id"]] <- mcp_session_id
  }

  result_msg <- list(jsonrpc = "2.0", id = id, result = result)

  if (identical(content_type, "text/event-stream")) {
    messages <- list(result_msg)
    if (length(notifications)) {
      messages <- c(messages, notifications)
    }
    body <- paste0(
      vapply(messages, function(msg) {
        json <- jsonlite::toJSON(msg, auto_unbox = TRUE, null = "null")
        paste0("event: message\ndata: ", json, "\n\n")
      }, FUN.VALUE = character(1L)),
      collapse = ""
    )
  } else {
    body <- jsonlite::toJSON(result_msg, auto_unbox = TRUE, null = "null")
  }

  shiny::httpResponse(
    status       = 200L,
    content_type = content_type,
    content      = body,
    headers      = headers
  )
}
