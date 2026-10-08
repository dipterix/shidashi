# find-rave.R: find the RAVE apps running on this computer, or open one in
# the browser
#
# Usage:
#   Rscript find-rave.R                  list RAVE sessions, newest first
#   Rscript find-rave.R --open=<port>    open the app on <port> in the
#                                        browser, once it answers
#
# Other options:
#   --root=<dir>          the RAVE session folder (default: ravedash's)
#   --testing-port=<n>    the port of the testing app (default 17283; 0 to
#                         skip it)
#
# A RAVE session is a folder listed by `ravedash::list_session()`. While its
# app runs, shidashi keeps `logs/server-info.log` there (app id, process id,
# port, URLs, MCP call log folder) and removes it when the app stops.
# `logs/base.log` in the same folder shows what the session is doing.

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  value <- args[startsWith(args, prefix)]
  if (!length(value)) {
    return(default)
  }
  substring(value[[1]], nchar(prefix) + 1L)
}

options(timeout = 3)

# `key: value` lines as a named list, or NULL
read_server_info <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  lines <- readLines(path, warn = FALSE)
  keys <- sub(":.*$", "", lines)
  values <- trimws(sub("^[^:]+:", "", lines))
  structure(as.list(values), names = keys)
}

# What `GET <url>mcp` says: list(status = "ok", app_id = ...) from a
# shidashi app, NULL when nothing answers
probe <- function(url) {
  answer <- tryCatch(
    suppressWarnings({
      con <- url(paste0(url, "mcp"), open = "r")
      on.exit(close(con))
      jsonlite::fromJSON(paste(readLines(con, warn = FALSE), collapse = ""))
    }),
    error = function(e) NULL
  )
  if (is.list(answer) && identical(answer$status, "ok")) answer else NULL
}

app_url <- function(x) {
  if (grepl("^https?://", x)) {
    if (!endsWith(x, "/")) x <- paste0(x, "/")
    return(x)
  }
  sprintf("http://127.0.0.1:%s/", x)
}

# ---- open an app in the browser ---------------------------------------------

open_target <- arg_value("open")
if (length(open_target)) {
  url <- app_url(open_target)
  answer <- probe(url)
  if (is.null(answer)) {
    cat(sprintf(
      "No shidashi app answers at %smcp, so nothing was opened.\n", url
    ))
    quit(save = "no", status = 1L)
  }
  utils::browseURL(url)
  cat(sprintf(paste(
    "Opened %s in the browser (app %s). Call `shidashi_sessions` until it",
    "lists the page, then `switch_module` to open a module.\n"
  ), url, if (length(answer$app_id)) answer$app_id else "?"))
  quit(save = "no", status = 0L)
}

# ---- list RAVE sessions -----------------------------------------------------

root <- arg_value("root")
sessions <- tryCatch(
  if (length(root)) {
    ravedash::list_session(path = root, order = "descend")
  } else {
    ravedash::list_session(order = "descend")
  },
  error = function(e) {
    cat("Cannot list RAVE sessions:", conditionMessage(e), "\n")
    list()
  }
)

cat("RAVE sessions on this computer, newest first:\n")
if (!length(sessions)) {
  cat("  (none)\n")
}
for (ii in seq_along(sessions)) {
  session <- sessions[[ii]]
  logs <- file.path(session$app_path, "logs")
  info <- read_server_info(file.path(logs, "server-info.log"))
  cat(sprintf("\n%d. %s\n", ii, session$session_id))
  if (is.null(info)) {
    cat("   status: not running (no logs/server-info.log)\n")
  } else {
    answer <- probe(info$url)
    status <- if (is.null(answer)) {
      sprintf("not running (port %s does not answer)", info$port)
    } else if (length(answer$app_id) && !identical(answer$app_id, info$app_id)) {
      sprintf("port %s answers, but as app %s, not this session's %s",
              info$port, answer$app_id, info$app_id)
    } else {
      sprintf("running (answers at %s)", info$url)
    }
    cat(sprintf("   status: %s\n", status))
    cat(sprintf("   url: %s\n   mcp: %s\n", info$url, info$mcp))
    cat(sprintf("   pid: %s; started: %s\n", info$pid, info$started))
    if (length(info$mcp_log)) {
      cat(sprintf("   MCP call log: %s\n",
                  file.path(info$mcp_log, "mcp-calls.log")))
    }
  }
  cat(sprintf("   base.log: %s\n", file.path(logs, "base.log")))
}

testing_port <- arg_value("testing-port", "17283")
if (!identical(testing_port, "0")) {
  answer <- probe(app_url(testing_port))
  cat(sprintf("\nTesting app on port %s: %s\n", testing_port,
              if (is.null(answer)) "not running" else
                sprintf("answers (app %s)", answer$app_id)))
}

cat(paste(
  "\nConnect to an app with `shidashi_connect` and its address (e.g.",
  "`127.0.0.1:<port>`). To open an app in the browser:",
  "`Rscript find-rave.R --open=<port>`.\n"
))
