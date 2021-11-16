#' @title Wrapper of shiny progress that can run without shiny
#' @param title the title of the progress
#' @param outputId the element id of \code{\link{progressOutput}}, or
#' \code{NULL} to use the default shiny progress
#' @param max max steps of the procedure
#' @param ... passed to initialization method of \code{\link[shiny]{Progress}}
#' @param quiet whether the progress needs to be quiet
#' @param session shiny session domain
#' @param shiny_auto_close whether to close the progress once function exits
#' @param log alternative log function
#' @return a list of functions that controls the progress
#' @examples
#'
#' {
#'   progress <- shiny_progress("Procedure A", max = 10)
#'   for(i in 1:10){
#'     progress$inc(sprintf("Step %s", i))
#'     Sys.sleep(0.1)
#'   }
#'   progress$close()
#'
#' }
#'
#' if(interactive()){
#'   library(shiny)
#'
#'   ui <- fluidPage(
#'     fluidRow(
#'       column(12, actionButton("click", "Click me"))
#'     )
#'   )
#'
#'   server <- function(input, output, session) {
#'     observeEvent(input$click, {
#'       progress <- shiny_progress("Procedure B", max = 10,
#'                                  shiny_auto_close = TRUE)
#'       for(i in 1:10){
#'         progress$inc(sprintf("Step %s", i))
#'         Sys.sleep(0.1)
#'       }
#'     })
#'   }
#'
#'   shinyApp(ui, server)
#' }
#'
#' @export
shiny_progress <- function (
  title, max = 1, ..., quiet = FALSE,
  session = shiny::getDefaultReactiveDomain(), shiny_auto_close = FALSE,
  log = NULL, outputId = NULL) {
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
  else if(length(outputId)){
    progress <- NULL
    inc <- function(detail, message = NULL, amount = 1, ...) {
      current <<- current + amount
      if(length(message)){ title <<- message[[1]] }
      session$sendCustomMessage("shidashi.set_progress", list(
        outputId = session$ns(outputId),
        value = current,
        max = max,
        description = paste(title, detail, sep = " - ")[[1]]
      ))
    }
    close <- function(message = "Finished") {
      closed <<- TRUE
      session$sendCustomMessage("shidashi.set_progress", list(
        outputId = outputId,
        value = max,
        max = max,
        description = message
      ))
    }
    reset <- function(detail = "", message = "", value = 0) {
      if(length(message)){
        title <<- message[[1]]
      } else {
        title <<- ""
      }
      if(length(detail)){
        detail <- paste(title, detail, sep = " - ")[[1]]
      } else {
        detail <- message
      }
      current <<- value
      session$sendCustomMessage("shidashi.set_progress", list(
        outputId = outputId,
        value = current,
        max = max,
        description = detail
      ))
    }
  } else {
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

#' Progress bar in shiny dashboard
#' @description For detailed usage, see demo application by
#' running \code{render()}.
#' @param outputId the element id of the progress
#' @param expr R expression that should return a named list of \code{value} and
#' \code{description}
#' @param env where to evaluate \code{expr}
#' @param quoted whether \code{expr} is quoted
#' @param outputArgs a list of other parameters in \code{progressOutput}
#' @param ... extra elements on the top of the progress bar
#' @param description descriptive message below the progress bar
#' @param width width of the progress
#' @param class progress class, default is \code{"bg-primary"}
#' @param value initial value, ranging from 0 to 100; default is 0
#' @param size size of the progress bar; choices are \code{"md"}, \code{"sm"},
#' \code{"xs"}
#' @return \code{progressOutput} returns 'HTML' tags containing progress bars
#' that can be rendered later via \code{\link{shiny_progress}} or
#' \code{renderProgress}. \code{renderProgress} returns shiny render functions
#' internally.
#' @examples
#'
#' library(shiny)
#' library(shidashi)
#' progressOutput("sales_report_prog1",
#'                description = "6 days left!",
#'                "Add Products to Cart",
#'                span(class="float-right", "123/150"),
#'                value = 123/150 * 100)
#'
#' # server function
#' server <- function(input, output, session, ...){
#'   output$sales_report_prog1 <- renderProgress({
#'     return(list(
#'       value = 140 / 150 * 100,
#'       description = "5 days left!"
#'     ))
#'   })
#' }
#'
#' @export
progressOutput <- function(
  outputId, ..., description = "Initializing",
  width = "100%", class = "bg-primary",
  value = 0, size = c("md", "sm", "xs")
){

  if(value < 0){
    value <- 0
  } else if(value > 100){
    value <- 100L
  }
  size <- match.arg(size)

  shiny::div(
    class = "shidashi-progress-output progress-group",
    id = outputId,
    style = sprintf("width: %s;", width),
    ...,
    shiny::div(
      class = sprintf("progress progress-%s", size),
      shiny::div(
        class = combine_class("progress-bar", class),
        style = sprintf("width: %.0f%%", value),
      )
    ),
    shiny::span(
      class = "progress-description progress-message",
      description
    ),
    shiny::span(
      class = "progress-description progress-error"
    )
  )

}

#' @rdname progressOutput
#' @export
renderProgress <- function(expr, env=parent.frame(), quoted=FALSE, outputArgs = list()) {

  func <- shiny::installExprFunction(expr, "func", env, quoted, label = "renderProgress")
  shiny::createRenderFunction(func, function(value, session, name, ...) {
    if(is.list(value)){
      description <- value$description
      value <- value$value
    } else {
      description <- NULL
    }
    if(!length(value)){
      value <- 0L
    } else {
      value <- as.integer(value)
    }

    if( value < 0L ){ value <- 0L }
    if( value > 100L ){ value <- 100L }
    list(
      value = value,
      description = description
    )

  }, progressOutput, outputArgs)

}

