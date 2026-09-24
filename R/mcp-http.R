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
  template_settings$set(mcp_app_id = app_id)

  dir.create(records_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(records_dir, paste0(app_id, ".json"))
  writeLines(
    jsonlite::toJSON(list(
      app_id  = app_id,
      appdir  = appdir,
      host    = host,
      port    = as.integer(port),
      pid     = Sys.getpid(),
      started = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
    ), auto_unbox = TRUE),
    path
  )

  # Keep the 20 newest records; the proxy skips the ones whose process is gone
  records <- list.files(records_dir, pattern = "\\.json$", full.names = TRUE)
  if (length(records) > 20L) {
    mtime <- file.info(records, extra_cols = FALSE)$mtime
    unlink(records[order(mtime, decreasing = TRUE)][-seq_len(20L)])
  }

  invisible(path)
}

# Chain the MCP handler in front of the app's HTTP handler. When `port` and
# `appdir` are given, also announce the app to the stdio proxy.
register_mcp_route <- function(app, port = NULL, appdir = NULL,
                               host = "127.0.0.1",
                               records_dir = mcp_app_records_dir(),
                              server_name = "shidashi") {
  if (length(port) == 1L && length(appdir) == 1L) {
    mcp_write_app_record(port = port, appdir = appdir, host = host,
                         records_dir = records_dir)
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
#' @param req the Rook request environment
#' @param scope `list(module)` from the URL
#' @return a `shiny::httpResponse`, or a promise of one
#' @noRd
mcp_http_handler <- function(req, scope = list()) {

  sweep_closed_sessions()

  body_raw <- tryCatch(req$rook.input$read(), error = function(e) raw(0))
  if (length(body_raw) == 0L) {
    return(mcp_json_error(NULL, -32700L, "Parse error: empty body"))
  }
  msg <- tryCatch(
    jsonlite::fromJSON(rawToChar(body_raw), simplifyVector = TRUE,
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
    return(mcp_json_error(
      id, -32600L, "Invalid Request: missing jsonrpc or method"
    ))
  }

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
