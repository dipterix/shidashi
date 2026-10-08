# ---- MCP call log ----
#
# Every request that reaches the MCP endpoint, and its reply, is written to
#
#   <cache>/MCP-logs/date-<yymmddTHHMMSS>_app-<app_id>/mcp-calls.log
#
# one folder per running app (named by its start time and `mcp_app_id()`),
# one line per event, at most 300 characters:
#
#   <time> [request|response|failed] [<tool or method>] id=<id> [<secs>s] <payload>
#
# The stdio proxy writes the calls that never reach the app into the same
# folder, marked `(proxy)`. Logging is off with
# `options(shidashi.mcp_log = FALSE)` or the environment variable
# `SHIDASHI_MCP_LOG=false` (or `0`); `shidashi.mcp_log_keep` (default 50) is
# the number of log folders kept.

mcp_log_max_chars <- 300L

mcp_log_enabled <- function() {
  if (isFALSE(as.logical(getOption("shidashi.mcp_log", TRUE))[1])) {
    return(FALSE)
  }
  env <- tolower(trimws(Sys.getenv("SHIDASHI_MCP_LOG", unset = "")))
  !env %in% c("false", "0")
}

mcp_log_root <- function() {
  file.path(shidashi_cache_dir(), "MCP-logs")
}

# The folder of this app's log. The start time is fixed for the process
# when the app record is written (or at the first call without a record).
mcp_log_dir <- function() {
  started <- template_settings$get("mcp_app_started")
  if (!inherits(started, "POSIXct")) {
    started <- Sys.time()
    template_settings$set(mcp_app_started = started)
  }
  file.path(mcp_log_root(), sprintf(
    "date-%s_app-%s", format(started, "%y%m%dT%H%M%S"), mcp_app_id()
  ))
}

# Keep the `keep` newest log folders; folder names start with the date
mcp_log_prune <- function(keep = getOption("shidashi.mcp_log_keep", 50L)) {
  root <- mcp_log_root()
  if (!dir.exists(root)) {
    return(invisible(character(0)))
  }
  folders <- sort(list.files(root, pattern = "^date-"), decreasing = TRUE)
  keep <- max(as.integer(keep)[1], 0L, na.rm = TRUE)
  removed <- folders[-seq_len(min(keep, length(folders)))]
  if (length(removed)) {
    unlink(file.path(root, removed), recursive = TRUE)
  }
  invisible(removed)
}

# One log line: a single line, cut to 300 characters
mcp_log_line <- function(type, name, id = NULL, payload = NULL,
                         elapsed = NULL, source = NULL, time = Sys.time()) {
  parts <- c(
    format(time, "%Y-%m-%d %H:%M:%OS3"),
    sprintf("[%s]", type),
    sprintf("[%s]", name),
    if (length(id)) sprintf("id=%s", paste(as.character(id), collapse = "")),
    if (length(elapsed)) sprintf("%.2fs", elapsed),
    if (length(source)) sprintf("(%s)", source),
    payload
  )
  line <- paste(parts, collapse = " ")
  line <- gsub("\r\n|\n|\r", "\\\\n", line)
  line <- gsub("\t", " ", line, fixed = TRUE)
  if (nchar(line) > mcp_log_max_chars) {
    line <- paste0(substr(line, 1L, mcp_log_max_chars - 3L), "...")
  }
  line
}

mcp_log_write <- function(line) {
  if (!mcp_log_enabled()) {
    return(invisible(FALSE))
  }
  tryCatch({
    dir <- mcp_log_dir()
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    con <- file(file.path(dir, "mcp-calls.log"), open = "ab")
    on.exit(close(con))
    writeBin(charToRaw(paste0(enc2utf8(line), "\n")), con)
    invisible(TRUE)
  }, error = function(e) {
    invisible(FALSE)
  })
}

mcp_log_json <- function(x) {
  if (!length(x)) {
    return("{}")
  }
  tryCatch(
    as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null",
                                  force = TRUE)),
    error = function(e) "{?}"
  )
}

mcp_log_reason <- function(message) {
  sprintf("{reason: %s}", jsonlite::toJSON(
    paste(as.character(message), collapse = " "), auto_unbox = TRUE
  ))
}

# A call being logged: when it started, and what it is
mcp_log_new_call <- function() {
  call <- new.env(parent = emptyenv())
  call$started <- Sys.time()
  call$name <- "?"
  call$id <- NULL
  call$method <- NULL
  call$notification <- FALSE
  call
}

mcp_log_elapsed <- function(call) {
  as.numeric(difftime(Sys.time(), call$started, units = "secs"))
}

# Record what the request is, and write its line
mcp_log_request <- function(call, method, id = NULL, params = NULL) {
  call$method <- method
  call$id <- id
  call$notification <- is.null(id)
  name <- method
  payload <- params
  if (identical(method, "tools/call")) {
    name <- paste(as.character(params$name), collapse = "")
    payload <- params$arguments
    if (identical(name, "shidashi_call")) {
      name <- paste0("shidashi_call:",
                     paste(as.character(params$arguments$tool), collapse = ""))
    }
  }
  call$name <- if (nzchar(name)) name else "?"
  mcp_log_write(mcp_log_line("request", call$name, id = id,
                             payload = mcp_log_json(payload)))
}

mcp_log_failed <- function(call, message) {
  mcp_log_write(mcp_log_line(
    "failed", call$name, id = call$id, elapsed = mcp_log_elapsed(call),
    payload = mcp_log_reason(message)
  ))
}

# The texts of a tool result
mcp_log_texts <- function(result) {
  texts <- vapply(result$content, function(item) {
    text <- item$text
    if (is.character(text)) paste(text, collapse = "\n") else ""
  }, "")
  paste(texts[nzchar(texts)], collapse = "\n")
}

# Skill scripts report a failed run as text: "Exit code: N" and, when they
# run out of time, a warning
mcp_log_script_failure <- function(text) {
  exit_code <- regmatches(text, regexpr("Exit code: -?[0-9]+", text))
  timed_out <- grepl("WARNING: Script timed out", text, fixed = TRUE)
  if (!timed_out &&
      (!length(exit_code) || identical(exit_code, "Exit code: 0"))) {
    return(NULL)
  }
  paste0(if (length(exit_code)) exit_code else "Timed out", "; ", text)
}

# Write the line for a reply (a `shiny::httpResponse`)
mcp_log_reply <- function(call, response) {
  if (isTRUE(call$notification)) {
    return(invisible(FALSE))
  }
  body <- tryCatch(
    jsonlite::fromJSON(paste(response$content, collapse = ""),
                       simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(body)) {
    return(mcp_log_failed(call, sprintf("HTTP %s without a JSON-RPC body",
                                        format(response$status))))
  }
  if (!is.null(body$error)) {
    return(mcp_log_failed(call, body$error$message))
  }
  result <- body$result
  payload <- NULL
  if (identical(call$method, "tools/call")) {
    text <- mcp_log_texts(result)
    if (isTRUE(result$isError)) {
      return(mcp_log_failed(call, text))
    }
    failure <- mcp_log_script_failure(text)
    if (!is.null(failure)) {
      return(mcp_log_failed(call, failure))
    }
    payload <- jsonlite::toJSON(text, auto_unbox = TRUE)
  } else if (identical(call$method, "tools/list")) {
    payload <- sprintf("{\"tools\":%d}", length(result$tools))
  } else {
    payload <- mcp_log_json(result)
  }
  mcp_log_write(mcp_log_line("response", call$name, id = call$id,
                             elapsed = mcp_log_elapsed(call),
                             payload = payload))
}

# Log the reply once it is there. A rejected promise is logged and stays
# rejected, so the HTTP behaviour does not change.
mcp_log_finish <- function(call, response) {
  if (promises::is.promise(response)) {
    return(promises::then(
      response,
      onFulfilled = function(value) {
        mcp_log_reply(call, value)
        value
      },
      onRejected = function(e) {
        mcp_log_failed(call, conditionMessage(e))
        stop(e)
      }
    ))
  }
  mcp_log_reply(call, response)
  response
}
