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

# Shiny session registry accessor.
# The backing fastmap lives inside .__shidashi_globals__. which is
# created by init_app() (called from global.R at app startup).
mcp_session_registry <- function(env = parent.frame()) {
  get_shidashi_globals(env = env)$mcp_session_registry
}

# ---------- Shiny session registry helpers --------------------------------

# Register a Shiny session for MCP access
# Internal
register_session_mcp <- function(session) {
  token <- session$token
  if (is.null(token) || !nzchar(token)) return(invisible(NULL))

  namespace <- session$ns(NULL)

  registry <- mcp_session_registry()
  registered <- registry$has(token)
  # Skip if registered
  if (registered && (length(namespace) != 1 || !nzchar(namespace))) {
    return(invisible(token))
  }

  entry <- registry$get(token, list())

  if (identical(entry$shiny_session, session)) {
    # already registered
    return(invisible(token))
  }
  if (!registered || !length(entry)) {
    entry <- list(
      shiny_session      = session,
      shidashi_module_id = NULL,
      mcp_session_ids    = character(),
      namespace          = namespace,
      url                = shiny::isolate(session$clientData$url_search),
      registered_at      = Sys.time(),
      tools              = structure(list(), names = character(0L))
    )
    message("Registered session token: ", token)
  } else {
    entry$shiny_session <- session
    entry$url <- shiny::isolate(session$clientData$url_search)
    entry$namespace <- namespace
  }

  registry$set(token, entry)

  
  # Send module token to root-level JS so the chatbot can bind
  if (length(namespace) == 1L && nzchar(namespace)) {
    # It does not matter who send out custom messages, can be root session or 
    # session proxy: they will be the same to JS
    session$sendCustomMessage(
      "shidashi.register_module_token",
      list(module_id = namespace, token = token)
    )
  }

  # Belt: onSessionEnded cleanup
  session$onSessionEnded(function() {
    mcp_unregister_session(session)
    mcp_sweep_closed_sessions()
  })

  invisible(token)
}

#' Remove a Shiny session from the MCP registry
#' @param session A Shiny session object
#' @keywords internal
#' @noRd
mcp_unregister_session <- function(session) {
  token <- session$token
  if (is.null(token) || !nzchar(token)) return(invisible(NULL))

  registry <- mcp_session_registry()
  if (registry$has(token)) {
    entry <- registry$get(token)
    if (identical(entry$shiny_session, session) || entry$shiny_session$isClosed()) {
      registry$remove(token)
      message("Unregistered session token: ", token)
    }
  }
  invisible(NULL)
}

# Given a MCP session ID, find shiny session tokens
mcp_tool_bound_shinysessions <- function(mcp_session_id) {
  if (length(mcp_session_id) != 1 || is.na(mcp_session_id) || !nzchar(mcp_session_id)) {
    return(character(0L))
  }
  registry <- mcp_session_registry()
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

  registry <- mcp_session_registry()
  lapply(tokens, function(token) {
    entry <- registry$get(token)
    entry$mcp_session_ids <- entry$mcp_session_ids[!entry$mcp_session_ids %in% mcp_session_id]
    registry$set(token, entry)
  })

  invisible(TRUE)
}

#' Sweep closed Shiny sessions from the registry
#'
#' Iterates all registered sessions and removes any where
#' \code{session$isClosed()} returns \code{TRUE}.
#' Called defensively on every MCP request.
#' @keywords internal
#' @noRd
mcp_sweep_closed_sessions <- function() {
  registry <- mcp_session_registry()
  tokens <- registry$keys()
  lapply(tokens, function(token) {
    entry <- registry$get(token)
    if (!length(entry) || !is.environment(entry$shiny_session)) {
      registry$remove(token)
      return()
    }
    closed <- tryCatch(entry$shiny_session$isClosed(), error = function(e) TRUE)
    if (isTRUE(closed)) {
      registry$remove(token)
    }
  })
  invisible(NULL)
}

# Look up a registry entry by Shiny session token.
# Returns the entry list, or NULL if not found / closed.
mcp_get_shiny_entry <- function(token) {
  if (length(token) != 1 || !is.character(token) || is.na(token) || !nzchar(token)) {
    return(NULL)
  }
  registry <- mcp_session_registry()
  if (!registry$has(token)) {
    return(NULL)
  }
  entry <- registry$get(token, missing = list())
  if (!is.environment(entry$shiny_session)) {
    registry$remove(token)
    return(NULL)
  }
  closed <- tryCatch(entry$shiny_session$isClosed(), error = function(e) TRUE)
  if (isTRUE(closed)) {
    registry$remove(token)
    return(NULL)
  }
  entry
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
  mcp_sweep_closed_sessions()

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

  # If bound to a Shiny session, add per-session tools
  bound_token <- mcp_tool_bound_shinysessions(mcp_session_id = mcp_session_id)
  if (length(bound_token)) {
    # Only use the first session: can only bind one at a time
    bound_token <- bound_token[[1]]
    entry <- mcp_get_shiny_entry(bound_token)
    if (length(entry)) {
      schema <- lapply(entry$tools, ellmer_tool_schema)
      tools <- c(tools, unname(schema))
    }
  }

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
  entry <- mcp_get_shiny_entry(bound_token)

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
  if (tool_name %in% names(entry$tools)) {
    tool_obj <- entry$tools[[tool_name]]
  } else {
    tool_obj <- NULL
  }

  if (is.null(tool_obj)) {
    result <- list(
      content = list(list(
        type = "text",
        text = paste0(
          "Tool '", tool_name, "' not found on bound session. ",
          "Available tools: ", paste(names(entry$tools), collapse = ", ")
        )
      )),
      isError = TRUE
    )
    return(mcp_json_result(id, result, mcp_session_id))
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
  registry <- mcp_session_registry()
  tokens <- registry$keys()

  sessions_info <- lapply(tokens, function(tk) {
    entry <- registry$get(tk)
    if (is.null(entry) || is.null(entry$shiny_session)) return(NULL)
    closed <- tryCatch(entry$shiny_session$isClosed(), error = function(e) TRUE)
    if (isTRUE(closed)) return(NULL)

    tool_names <- character(0)
    if (is.list(entry$tools) && length(entry$tools) > 0L) {
      tool_names <- names(entry$tools)
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
  entry <- mcp_get_shiny_entry(token)

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
  entry <- mcp_get_shiny_entry(token)

  # Bind MCP session to Shiny token
  entry$mcp_session_ids <- unique(c(entry$mcp_session_ids, mcp_session_id))
  registry <- mcp_session_registry()
  registry$set(token, entry)

  # Build response with info about the bound session
  tool_info <- lapply(entry$tools, function(tool_obj) {
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
      " The MCP tool list has been updated.",
      " The following tools are NOW available as top-level MCP tools",
      " you can call directly: ",
      paste(tool_names, collapse = ", "), ".",
      " Call tools/list to see their full schemas (<- it's UPDATED!)."
    )
  } else {
    msg <- paste0(
      "Successfully bound to Shiny session '", token, "'.",
      " No per-session tools are registered on this session."
    )
  }

  detail <- as.character(jsonlite::toJSON(info, auto_unbox = TRUE, null = "null"))
  text <- paste0(msg, "\n\nDetails:\n", detail)
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

  entry <- mcp_get_shiny_entry(bound_token)
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

  tool_info <- lapply(entry$tools, function(tool_obj) {
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
