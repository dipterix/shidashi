# ---- MCP (Model Context Protocol) HTTP endpoint ----
#
# A Streamable HTTP MCP endpoint that lives inside the same httpuv process
# as the Shiny app. Terms:
#
#   app      one running shidashi R process serving one app directory;
#            one app is one user. Identified by `mcp_app_id()`.
#   open module  a Shiny session running a module; tool calls run there
#                (see mcp-module.R).
#
# URLs:
#   /mcp            the module is chosen per call
#   /mcp/{module}   every call is limited to matching open modules (a module
#                   id, a handle such as `demo@4f542d`, or a token prefix)
#
# One host and port serve one app, so the URL never names the app. Behind a
# reverse proxy (nginx, RStudio Server's `/p/<id>/`), the proxy's prefix is
# stripped before the request reaches the app. `mcp_app_id()` still
# identifies the app in `GET /mcp`, app records, and `shidashi_sessions`.
#
# The server is stateless: it issues no `Mcp-Session-Id` and remembers
# nothing about agent connections.

#' Identifier of the running shidashi app
#'
#' The first eight characters of a digest of the app directory and the
#' process id, so it changes when the app restarts.
#' @noRd
mcp_app_id <- function() {
  app_id <- template_settings$get("mcp_app_id")
  if (length(app_id) == 1L && is.character(app_id) && nzchar(app_id)) {
    return(app_id)
  }
  appdir <- normalizePath(template_root(), winslash = "/", mustWork = FALSE)
  substr(digest::digest(paste(appdir, Sys.getpid())), 1L, 8L)
}

# Split an MCP URL path into its optional module. Returns NULL when the path
# is not a valid MCP path.
mcp_parse_path <- function(path) {
  if (!is.character(path) || length(path) != 1L ||
      !grepl("^/mcp(/|$)", path)) {
    return(NULL)
  }
  rest <- sub("/+$", "", sub("^/mcp/?", "", path))
  segments <- character(0)
  if (nzchar(rest)) {
    segments <- strsplit(rest, "/", fixed = TRUE)[[1]]
    segments <- vapply(segments, utils::URLdecode, "", USE.NAMES = FALSE)
  }
  if (length(segments) > 1L || !all(nzchar(segments))) {
    return(NULL)
  }
  list(module = if (length(segments)) segments[[1L]])
}

# The shidashi cache folder, holding:
#   launchers.json      saved launchers (save_launcher)
#   saved_apps/<id>/    app copies (save_launcher(copy_app = TRUE))
#   mcp_server/         the stdio proxy, `apps/` records, and `logs/`
# The option `shidashi.cache_dir`, then the environment variable
# `SHIDASHI_CACHE_DIR` (set by the proxy for the apps it starts), override
# the default in the user's cache directory.
shidashi_cache_dir <- function() {
  is_dir_string <- function(x) {
    length(x) == 1L && is.character(x) && !is.na(x) && nzchar(x)
  }
  dir <- getOption("shidashi.cache_dir")
  if (is_dir_string(dir)) {
    return(dir)
  }
  dir <- Sys.getenv("SHIDASHI_CACHE_DIR", unset = "")
  if (is_dir_string(dir)) {
    return(dir)
  }
  tools::R_user_dir("shidashi", which = "cache")
}

# The folder holding the stdio proxy and app records (`apps/`)
mcp_server_dir <- function() {
  file.path(shidashi_cache_dir(), "mcp_server")
}

# Where running apps announce themselves to the stdio proxy
mcp_app_records_dir <- function() {
  file.path(mcp_server_dir(), "apps")
}

#' Announce a running app to the stdio proxy
#'
#' Writes `<app_id>.json` with the app id, app directory, host, port,
#' process id, and start time, and fixes the id returned by `mcp_app_id()`
#' for this process. The proxy ignores records whose process has exited.
#' @return the record path, invisibly
#' @noRd
mcp_write_app_record <- function(port, appdir, host = "127.0.0.1",
                                 records_dir = mcp_app_records_dir()) {
  appdir <- normalizePath(appdir, winslash = "/", mustWork = TRUE)
  app_id <- substr(digest::digest(paste(appdir, Sys.getpid())), 1L, 8L)
  started <- Sys.time()
  template_settings$set(mcp_app_id = app_id, mcp_app_started = started)

  record <- list(
    app_id  = app_id,
    appdir  = appdir,
    host    = host,
    port    = as.integer(port),
    pid     = Sys.getpid(),
    started = format(started, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
  )
  # Where the proxy writes the calls that never reach this app
  if (mcp_log_enabled()) {
    record$log_dir <- mcp_log_dir()
    mcp_log_prune()
  }

  dir.create(records_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(records_dir, paste0(app_id, ".json"))
  writeLines(jsonlite::toJSON(record, auto_unbox = TRUE), path)

  mcp_write_server_info(appdir, record, started = started)

  # Keep the 20 newest records; the proxy skips the ones whose process is gone
  records <- list.files(records_dir, pattern = "\\.json$", full.names = TRUE)
  if (length(records) > 20L) {
    mtime <- file.info(records, extra_cols = FALSE)$mtime
    unlink(records[order(mtime, decreasing = TRUE)][-seq_len(20L)])
  }

  invisible(path)
}

# The host part of a URL that reaches `host` from this computer: a wildcard
# listen address means this computer
mcp_url_host <- function(host) {
  if (!length(host) || !nzchar(host) || host %in% c("0.0.0.0", "::")) {
    host <- "127.0.0.1"
  }
  if (grepl(":", host, fixed = TRUE)) {
    host <- sprintf("[%s]", host)
  }
  host
}

# Where the app's `logs/server-info.log` is
mcp_server_info_path <- function(appdir) {
  file.path(appdir, "logs", "server-info.log")
}

#' Write `<appdir>/logs/server-info.log`
#'
#' One `key: value` per line: the app id, process id, start time, host,
#' port, the app and MCP URLs, and the MCP call log folder. Agents read it
#' to find a running app (for example a RAVE session folder). It is removed
#' when the app stops (see `mcp_remove_app_files()`). Also keeps the app URL
#' in `template_settings` for messages that tell agents how to open it.
#' @noRd
mcp_write_server_info <- function(appdir, record, started = Sys.time()) {
  url <- sprintf("http://%s:%d/", mcp_url_host(record$host), record$port)
  template_settings$set(mcp_app_url = url)
  lines <- c(
    paste("app_id:", record$app_id),
    paste("pid:", record$pid),
    paste("started:", format(started, "%Y-%m-%d %H:%M:%S %Z")),
    paste("host:", record$host),
    paste("port:", record$port),
    paste("url:", url),
    paste0("mcp: ", url, "mcp"),
    if (length(record$log_dir)) paste("mcp_log:", record$log_dir)
  )
  path <- mcp_server_info_path(appdir)
  tryCatch({
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    writeLines(lines, path)
  }, error = function(e) {
    warning("Cannot write ", path, ": ", conditionMessage(e), call. = FALSE)
  })
  invisible(path)
}

# Remove the app record and server info of this process; files that name
# another process (an app started since in the same folder) stay
mcp_remove_app_files <- function(record_path, info_path) {
  pid <- Sys.getpid()
  record_pid <- tryCatch(jsonlite::read_json(record_path)$pid,
                         error = function(e) NULL)
  if (identical(as.integer(record_pid), pid)) {
    unlink(record_path)
  }
  info <- tryCatch(readLines(info_path, warn = FALSE),
                   error = function(e) character(0))
  info_pid <- sub("^pid:[[:space:]]*", "", info[startsWith(info, "pid:")])
  if (identical(info_pid, as.character(pid))) {
    unlink(info_path)
  }
  invisible()
}

# What an agent can do when no browser page is connected to the app: open
# the app's URL (known once the app record is written)
mcp_open_page_hint <- function() {
  url <- template_settings$get("mcp_app_url")
  if (!(length(url) == 1L && is.character(url) && nzchar(url))) {
    return("Ask the user to open the app in the browser.")
  }
  sprintf(
    paste(
      "Open the app in a browser first. Give the user this one-click link:",
      "[Open the dashboard](%1$s). On the computer that runs the app, you",
      "may instead check that `GET %1$smcp` answers, then open the link with",
      "`utils::browseURL()`. Then call `shidashi_sessions` until it lists",
      "the page."
    ),
    url
  )
}

# Chain the MCP handler in front of the app's HTTP handler. When `port` and
# `appdir` are given, also announce the app to the stdio proxy (the app
# record and `logs/server-info.log`); both are removed when the app stops.
register_mcp_route <- function(app, port = NULL, appdir = NULL,
                               host = "127.0.0.1",
                               records_dir = mcp_app_records_dir(),
                              server_name = "shidashi") {
  if (length(port) == 1L && length(appdir) == 1L) {
    record_path <- mcp_write_app_record(port = port, appdir = appdir,
                                        host = host,
                                        records_dir = records_dir)
    info_path <- mcp_server_info_path(
      normalizePath(appdir, winslash = "/", mustWork = TRUE)
    )
    # Outside a server function, this runs when the app exits: a normal
    # stop, an interrupt, or an error while starting
    shiny::onStop(function() {
      mcp_remove_app_files(record_path, info_path)
    }, session = NULL)
  }

  default_handler <- app$httpHandler
  app$httpHandler <- function(req) {
    response <- mcp_route_request(req, server_name = server_name)
    if (!is.null(response)) {
      return(response)
    }
    default_handler(req)
  }

  # Exclude /mcp from httpuv static-path handling so POST requests reach
  # the R handler instead of being rejected with 400.
  app$staticPaths <- c(app$staticPaths, list(mcp = httpuv::excludeStaticPath()))

  app
}

# Handle a request under /mcp; NULL for any other path
mcp_route_request <- function(req, server_name = "shidashi") {
  path <- req$PATH_INFO
  if (!is.character(path) || length(path) != 1L ||
      !grepl("^/mcp(/|$)", path)) {
    return(NULL)
  }

  scope <- mcp_parse_path(path)
  if (is.null(scope)) {
    return(mcp_json_error(
      id = NULL, code = -32600L, status = 404L,
      message = "Unknown MCP path. Use /mcp or /mcp/{module}."
    ))
  }

  switch(
    req$REQUEST_METHOD,
    "POST" = mcp_http_handler(req, scope),
    "GET" = shiny::httpResponse(
      200L, "application/json",
      jsonlite::toJSON(list(
        status  = "ok",
        server  = server_name,
        app_id  = mcp_app_id(),
        message = sprintf("%s MCP endpoint active. Use POST with JSON-RPC 2.0.", server_name)
      ), auto_unbox = TRUE)
    ),
    shiny::httpResponse(405L, "text/plain", "Method Not Allowed")
  )
}

#' Handle an MCP JSON-RPC request
#'
#' Answers the request and writes it and its reply to the MCP call log
#' (see mcp-log.R).
#' @param req the Rook request environment
#' @param scope `list(module)` from the URL
#' @return a `shiny::httpResponse`, or a promise of one
#' @noRd
mcp_http_handler <- function(req, scope = list()) {
  call <- mcp_log_new_call()
  response <- tryCatch(
    mcp_http_dispatch(req, scope, call),
    error = function(e) {
      mcp_log_failed(call, conditionMessage(e))
      stop(e)
    }
  )
  mcp_log_finish(call, response)
}

# Parse and answer one JSON-RPC request; `call` (from mcp_log_new_call())
# records what it is for the log
mcp_http_dispatch <- function(req, scope, call) {

  sweep_closed_sessions()

  body_raw <- tryCatch(req$rook.input$read(), error = function(e) raw(0))
  if (length(body_raw) == 0L) {
    return(mcp_json_error(NULL, -32700L, "Parse error: empty body"))
  }
  body_text <- rawToChar(body_raw)
  msg <- tryCatch(
    jsonlite::fromJSON(body_text, simplifyVector = TRUE,
                       simplifyDataFrame = FALSE, simplifyMatrix = FALSE),
    error = function(e) NULL
  )
  if (is.null(msg)) {
    return(mcp_json_error(NULL, -32700L, "Parse error: invalid JSON"))
  }

  id     <- msg$id
  method <- msg$method
  params <- msg$params

  if (!identical(msg$jsonrpc, "2.0") || !is.character(method) ||
      length(method) != 1L) {
    call$id <- id
    return(mcp_json_error(
      id, -32600L, "Invalid Request: missing jsonrpc or method"
    ))
  }

  # The log shows the arguments as the client sent them: unsimplified, so a
  # one-element array stays an array
  mcp_log_request(call, method = method, id = id, params = tryCatch(
    jsonlite::fromJSON(body_text, simplifyVector = FALSE)$params,
    error = function(e) params
  ))

  # Notifications (no id) need no reply
  if (is.null(id)) {
    return(shiny::httpResponse(status = 202L, content_type = "", content = ""))
  }

  tryCatch(
    switch(
      method,
      "initialize" = mcp_handle_initialize(id, params),
      "tools/list" = mcp_handle_tools_list(id, params),
      "tools/call" = mcp_handle_tools_call(id, params, scope),
      "ping"       = mcp_json_result(id, structure(list(), names = character(0L))),
      mcp_json_error(id, -32601L, paste0("Method not found: ", method))
    ),
    error = function(e) {
      mcp_json_error(id, -32603L, paste0("Internal error: ", conditionMessage(e)))
    }
  )
}

# ---------- JSON-RPC responses ---------------------------------------------

mcp_json_error <- function(id, code, message, status = 200L) {
  body <- jsonlite::toJSON(
    list(
      jsonrpc = "2.0",
      id      = id,
      error   = list(code = code, message = message)
    ),
    auto_unbox = TRUE,
    null = "null"
  )
  shiny::httpResponse(
    status       = status,
    content_type = "application/json",
    content      = body
  )
}

mcp_json_result <- function(id, result) {
  body <- jsonlite::toJSON(
    list(jsonrpc = "2.0", id = id, result = result),
    auto_unbox = TRUE,
    null = "null"
  )
  shiny::httpResponse(
    status       = 200L,
    content_type = "application/json",
    content      = body
  )
}
