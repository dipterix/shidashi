# From my own dipsaus package

#' @export
shiny_progress <- function (title, max = 1, ..., quiet = FALSE, session = shiny::getDefaultReactiveDomain(), shiny_auto_close = FALSE, log = NULL) {
  if (missing(title) || is.null(title)) {
    title <- ""
  }
  if (length(title) > 1) {
    title <- paste(title, collapse = "")
  }
  if (inherits(session, c("ShinySession", "session_proxy",
                          "R6"))) {
    within_shiny <- TRUE
  }
  else {
    within_shiny <- FALSE
  }
  current <- 0
  closed <- FALSE
  get_value <- function() {
    current
  }
  is_closed <- function() {
    closed
  }
  logger <- function(..., .quiet = quiet, level = "DEFAULT",
                     bullet = "play") {
    if (!.quiet) {
      if (is.function(log)) {
        log(...)
      }
      else {
        s <- paste(..., collapse = "", sep = "")
        nz <- nchar(s, allowNA = TRUE, keepNA = TRUE)
        w <- getOption("width", 80L)
        s <- paste0(s, paste(rep(' ', w - nz %% w), collapse = ""))
        message("\r", s, appendLF = identical(bullet, "stop"))
      }
    }
  }
  if (quiet || !within_shiny) {
    progress <- NULL
    logger(sprintf("[%s]: initializing...", title), level = "DEFAULT",
           bullet = "play")
    inc <- function(detail, message = NULL, amount = 1, ...) {
      stopifnot(!closed)
      quiet <- c(list(...)[["quiet"]], quiet)[[1]]
      if (!is.null(message) && length(message) == 1) {
        title <<- message
      }
      current <<- amount + current
      logger(sprintf("[%s]: %s (%d out of %d)", title,
                     detail, current, max), level = "DEFAULT", bullet = "arrow_right",
             .quiet = quiet)
    }
    close <- function(message = "Finished") {
      closed <<- TRUE
      logger(message, level = "DEFAULT", bullet = "stop")
    }
    reset <- function(detail = "", message = "", value = 0) {
      title <<- message
      current <<- value
    }
  }
  else {
    progress <- shiny::Progress$new(session = session, max = max,
                                    ...)
    inc <- function(detail, message = NULL, amount = 1, ...) {
      if (!is.null(message) && length(message) == 1) {
        title <<- message
      }
      progress$inc(detail = detail, message = title, amount = amount)
    }
    close <- function(message = "Finished") {
      if (!closed) {
        progress$close()
        closed <<- TRUE
      }
    }
    reset <- function(detail = "", message = "", value = 0) {
      title <<- message
      current <<- value
      progress$set(value = value, message = title, detail = detail)
    }
    if (shiny_auto_close) {
      parent_frame <- parent.frame()
      do.call(on.exit, list(substitute(close()), add = TRUE),
              envir = parent_frame)
    }
    inc(detail = "Initializing...", amount = 0)
  }
  return(list(.progress = progress, inc = inc, close = close,
              reset = reset, get_value = get_value, is_closed = is_closed))
}
