# ---- MCP (Model Context Protocol) JSON-RPC 2.0 handler for shidashi ----
#
# This module implements a Streamable HTTP MCP endpoint that lives inside
# the same httpuv process as the Shiny app.  No sidecar process needed.
#
# Entry point: `mcp_http_handler(req)` is called from `adminlte_ui()`
# when `req$PATH_INFO == "/mcp"` and `req$REQUEST_METHOD == "POST"`.
#
# Phase 1: static hello-world tool to prove the JSON tunnel works.

# Package-level session registry (persists across HTTP requests)
#
# Single fastmap: session$token -> entry
# Entry structure:
#   list(
#     shiny_session      = <ShinySession>,   # live session object
#     shidashi_module_id = NULL,             # reserved for Phase 3
#     namespace          = "",               # session namespace string
#     url                = "",               # client URL at connect time
#     registered_at      = <POSIXct>         # registration timestamp
#   )
mcp_session_registry <- local({
  registry <- NULL

  function() {
    if (is.null(registry)) {
      registry <<- fastmap::fastmap()
    }
    registry
  }
})

# ---------- Shiny session registry helpers --------------------------------

#' Register a Shiny session for MCP access
#'
#' @export
register_session_mcp <- function(session, meta = list()) {
  token <- session$token
  if (is.null(token) || !nzchar(token)) return(invisible(NULL))

  namespace <- session$ns(NULL)

  registry <- mcp_session_registry()
  registered <- registry$has(token)
  # Skip if registered
  if (registered && (length(namespace) != 1 || !nzchar(namespace))) { return(invisible(token)) }

  entry <- registry$get(token, list(
    shiny_session      = session,
    shidashi_module_id = NULL,
    namespace          = namespace,
    url                = shiny::isolate(session$clientData$url_search),
    registered_at      = Sys.time()
  ))
  entry$shiny_session <- session
  entry$url <- shiny::isolate(session$clientData$url_search)
  entry$namespace <- namespace
  registry$set(token, entry)
  if (!registered) {
    message("Registered session token: ", token)
  }

  # Belt: onSessionEnded cleanup
  session$onSessionEnded(function() {
    mcp_unregister_session(session)
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
  for (tk in tokens) {
    entry <- registry$get(tk)
    if (is.null(entry) || is.null(entry$shiny_session)) {
      registry$remove(tk)
    } else {
      closed <- tryCatch(entry$shiny_session$isClosed(), error = function(e) TRUE)
      if (isTRUE(closed)) {
        registry$remove(tk)
      }
    }
  }
  invisible(NULL)
}

# Look up a registry entry by Shiny session token.
# Returns the entry list, or NULL if not found / closed.
mcp_get_shiny_entry <- function(token) {
  if (is.null(token) || !nzchar(token)) return(NULL)
  registry <- mcp_session_registry()
  entry <- registry$get(token)
  if (is.null(entry) || is.null(entry$shiny_session)) return(NULL)
  closed <- tryCatch(entry$shiny_session$isClosed(), error = function(e) TRUE)
  if (isTRUE(closed)) {
    registry$remove(token)
    return(NULL)
  }
  entry
}
# ---------- app-level HTTP handler ----------------------------------------

#' Create an HTTP handler for the MCP endpoint
#'
#' Returns a function suitable for assignment to
#' \code{shinyApp()$httpHandler}. This handler intercepts POST and DELETE
#' requests to \code{/mcp} before Shiny's internal routing, which only
#' passes GET requests to the UI function.
#'
#' @return A function taking a Rook \code{req} and returning either a
#'   \code{shiny::httpResponse} (for MCP requests) or \code{NULL}
#'   (pass-through to Shiny).
#' @keywords internal
mcp_app_handler <- function(app) {
  default_handlers <- app$httpHandler
  mcp_handler <- function(req) {
    if (!identical(req$PATH_INFO, "/mcp")) return(NULL)
    if (identical(req$REQUEST_METHOD, "POST")) {
      return(mcp_http_handler(req))
    }
    if (identical(req$REQUEST_METHOD, "DELETE")) {
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

  function(req) {
    response <- mcp_handler(req)
    if (!is.null(response)) {
      return(response)
    }
    return(default_handlers(req))
  }
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
#' @keywords internal
mcp_http_handler <- function(req) {

  # --- sweep stale Shiny sessions (defensive) ---------------------------
  mcp_sweep_closed_sessions()

  # --- read body --------------------------------------------------------
  body_raw <- tryCatch(
    req$rook.input$read(),
    error = function(e) raw(0)
  )
  if (length(body_raw) == 0L) {
    return(mcp_json_error(
      id = NULL,
      code = -32700L,
      message = "Parse error: empty body"
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
      message = "Parse error: invalid JSON"
    ))
  }

  # --- validate JSON-RPC envelope ---------------------------------------
  jsonrpc <- msg$jsonrpc
  method  <- msg$method
  id      <- msg$id
  params  <- msg$params

  if (!identical(jsonrpc, "2.0") || !is.character(method) ||
      length(method) != 1L) {
    return(mcp_json_error(
      id = id,
      code = -32600L,
      message = "Invalid Request: missing jsonrpc or method"
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
  mcp_session_id <- req$HTTP_MCP_SESSION_ID  # may be NULL on initialize

  result <- tryCatch(
    switch(
      method,
      "initialize"  = mcp_handle_initialize(id, params),
      "tools/list"  = mcp_handle_tools_list(id, params, mcp_session_id),
      "tools/call"  = mcp_handle_tools_call(id, params, mcp_session_id),
      # default: method not found
      mcp_json_error(
        id = id,
        code = -32601L,
        message = paste0("Method not found: ", method)
      )
    ),
    error = function(e) {
      mcp_json_error(
        id = id,
        code = -32603L,
        message = paste0("Internal error: ", conditionMessage(e))
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
    list(Sys.time(), Sys.getpid(), sample.int(.Machine$integer.max, 1L)),
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
        capabilities    = list(tools = setNames(list(), character(0))),
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


#' Handle MCP `tools/list` request
#' @keywords internal
#' @noRd
mcp_handle_tools_list <- function(id, params, mcp_session_id) {

  tools <- list(
    list(
      name        = "hello_world",
      description = "Returns a greeting. Used to verify the MCP tunnel works.",
      inputSchema = list(
        type       = "object",
        properties = list(
          name = list(
            type        = "string",
            description = "Name to greet"
          )
        ),
        required = list("name")
      )
    ),
    list(
      name        = "list_shinysessions",
      description = "List all active Shiny sessions. Each session represents a browser tab or iframe. Returns token, namespace, URL, and registration time.",
      inputSchema = list(
        type       = "object",
        properties = setNames(list(), character(0))
      )
    ),
    list(
      name        = "get_shiny_input_values",
      description = "Read Shiny input values from a session. Call list_shinysessions first to obtain a token. If input_ids is empty, returns all inputs.",
      inputSchema = list(
        type       = "object",
        properties = list(
          token = list(
            type        = "string",
            description = "The session token from list_shinysessions"
          ),
          input_ids = list(
            type        = "array",
            items       = list(type = "string"),
            description = "Input IDs to read. If empty or omitted, returns all input values."
          )
        ),
        required = list("token")
      )
    )
  )

  body <- jsonlite::toJSON(
    list(
      jsonrpc = "2.0",
      id      = id,
      result  = list(tools = tools)
    ),
    auto_unbox = TRUE,
    null = "null"
  )

  mcp_json_response(200L, body, mcp_session_id)
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
      message = "Invalid params: missing or invalid tool name"
    ))
  }

  result <- switch(
    tool_name,
    "hello_world"           = mcp_tool_hello_world(arguments),
    "list_shinysessions"    = mcp_tool_list_shinysessions(arguments),
    "get_shiny_input_values" = mcp_tool_get_shiny_input_values(arguments),
    # default: tool not found
    list(
      content = list(list(
        type = "text",
        text = paste0(
          "Unknown tool: '", tool_name,
          "'. Call tools/list to see available tools."
        )
      )),
      isError = TRUE
    )
  )

  body <- jsonlite::toJSON(
    list(
      jsonrpc = "2.0",
      id      = id,
      result  = result
    ),
    auto_unbox = TRUE,
    null = "null"
  )

  mcp_json_response(200L, body, mcp_session_id)
}

# ---------- tool implementations -----------------------------------------

#' Phase 1 hello-world tool
#' @keywords internal
#' @noRd
mcp_tool_hello_world <- function(arguments) {
  name <- arguments$name
  if (!is.character(name) || length(name) != 1L) {
    name <- "World"
  }
  greeting <- paste0("Hello, ", name, "!")
  list(
    content = list(list(
      type = "text",
      text = greeting
    )),
    isError = FALSE
  )
}

#' List active Shiny sessions
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
    list(
      token         = tk,
      namespace     = entry$namespace,
      url           = entry$url,
      registered_at = format(entry$registered_at, "%Y-%m-%dT%H:%M:%S")
    )
  })
  sessions_info <- Filter(Negate(is.null), sessions_info)

  text <- as.character(jsonlite::toJSON(sessions_info, auto_unbox = TRUE, null = "null"))
  list(
    content = list(list(
      type = "text",
      text = text
    )),
    isError = FALSE
  )
}

#' Read Shiny input values from a session identified by token
#' @keywords internal
#' @noRd
mcp_tool_get_shiny_input_values <- function(arguments) {
  # --- resolve session by token -----------------------------------------
  token <- arguments$token
  if (!is.character(token) || length(token) != 1L || !nzchar(token)) {
    return(list(
      content = list(list(
        type = "text",
        text = "Error: 'token' is required. Call list_shinysessions to obtain a valid token."
      )),
      isError = TRUE
    ))
  }

  entry <- mcp_get_shiny_entry(token)
  if (is.null(entry)) {
    return(list(
      content = list(list(
        type = "text",
        text = paste0(
          "Error: No active session for token '", token,
          "'. Call list_shinysessions for current sessions."
        )
      )),
      isError = TRUE
    ))
  }

  session <- entry$shiny_session

  # --- read inputs -------------------------------------------------------
  input_ids <- arguments$input_ids
  values <- tryCatch({
    if (is.null(input_ids) || length(input_ids) == 0L) {
      # Return all inputs
      shiny::isolate(shiny::reactiveValuesToList(session$input))
    } else {
      # Return specific inputs
      vals <- setNames(
        lapply(input_ids, function(id) {
          shiny::isolate(session$input[[id]])
        }),
        input_ids
      )
      vals
    }
  }, error = function(e) {
    return(list(.error = conditionMessage(e)))
  })

  if (!is.null(values$.error)) {
    return(list(
      content = list(list(
        type = "text",
        text = paste0("Error reading inputs: ", values$.error)
      )),
      isError = TRUE
    ))
  }

  text <- as.character(jsonlite::toJSON(values, auto_unbox = TRUE, null = "null",
                                        force = TRUE))
  list(
    content = list(list(
      type = "text",
      text = text
    )),
    isError = FALSE
  )
}

# ---------- JSON helpers -------------------------------------------------

#' Build a JSON-RPC 2.0 error response
#' @keywords internal
#' @noRd
mcp_json_error <- function(id, code, message) {
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
    content      = body
  )
}


#' Build a JSON HTTP response with optional Mcp-Session-Id header
#' @keywords internal
#' @noRd
mcp_json_response <- function(status, body, mcp_session_id = NULL) {
  headers <- list()
  if (!is.null(mcp_session_id) && nzchar(mcp_session_id)) {
    headers[["Mcp-Session-Id"]] <- mcp_session_id
  }
  shiny::httpResponse(
    status       = status,
    content_type = "application/json",
    content      = body,
    headers      = headers
  )
}
