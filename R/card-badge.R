#' Create a badge widget located at card header
#' @param text inner text content of the badge
#' @param class additional 'HTML' class of the badge; for
#' \code{set_card_badge}, this is the class selector of the badge that is
#' to be changed
#' @param ... additional 'HTML' tag attributes
#' @param id the badge 'HTML' ID to be changed, will be enclosed with
#' session namespace \code{session$ns(id)} automatically.
#' @param add_class,remove_class add or remove class
#' @param session shiny session
#' @param event_name name of the event to trigger
#' @examples
#'
#' library(shidashi)
#'
#' # UI: a Bootstrap badge with green background
#' card_badge("Ready", class = "bg-green shidashi-output-status")
#'
#' # server
#' server <- function(input, output, session) {
#'
#'   shiny::observe({
#'
#'     # ... check if the inputs have changed
#'
#'     set_card_badge(
#'       class = "shidashi-output-status",
#'       text = "Refresh needed",
#'       add_class = "bg-warning",
#'       remove_class = "bg-success disabled"
#'     )
#'
#'   })
#'
#' }
#'
#' @export
card_badge <- function(text = NULL, class = NULL, ...) {
  if (!length(text) || nchar(text) == 0) {
    text <- ""
  }
  class <- combine_class("right badge shidashi-card-badge", class)
  shiny::span(class = class, text, ...)
}

#' @rdname card_badge
#' @export
card_recalculate_badge <- function(
    text = "Recalculate needed", class = NULL, event_name = "run_analysis", ...) {
  stopifnot("`event_name` must be non-empty string" = nzchar(event_name))
  card_badge(
    text = text,
    class = combine_class(
      "btn btn-default shidashi-button shidashi-button-recalculate shidashi-output-status bg-yellow",
      class
    ),
    `data-shidashi-type` = event_name,
    `data-shidashi-action` = "shidashi-button",
    `data-shidashi-dynamic` = "true",
    ...
  )
}

#' @rdname card_badge
#' @export
enable_recalculate_badge <- function(
    text = "Recalculate needed", ...) {
  set_card_badge(
    text = text, class = "shidashi-button-recalculate",
    add_class = "btn btn-default shidashi-button bg-yellow shidashi-button-recalculate",
    remove_class = "disabled"
  )
}

#' @rdname card_badge
#' @export
disable_recalculate_badge <- function(
    text = "Up-to-date", ...) {
  set_card_badge(
    text = text, class = "shidashi-button-recalculate",
    remove_class = "btn btn-default shidashi-button bg-yellow",
    add_class = "disabled"
  )
}

#' @rdname card_badge
#' @export
set_card_badge <- function(
    id = NULL, class = NULL,
    text = NULL, add_class = NULL, remove_class = NULL,
    session = shiny::getDefaultReactiveDomain()) {
  if (!length(id) && !length(class)) {
    class <- "shidashi-card-badge"
  }
  if ( is.null(session) ) { return() }

  if (length(id)) {
    selector <- sprintf("#%s.shidashi-card-badge", session$ns(id))
  } else if (identical(class, "shidashi-card-badge")) {
    selector <- ".shidashi-card-badge"
  } else {
    selector <- sprintf(".%s.shidashi-card-badge", class)
  }

  if (length(text)) {
    session$sendCustomMessage(
      "shidashi.set_html",
      message = list(
        selector = selector,
        content = text
      )
    )
  }
  if (length(add_class)) {
    add_class <- trimws(unlist(strsplit(add_class, " ")))
    lapply(add_class, function(cls) {
      session$sendCustomMessage(
        "shidashi.add_class",
        message = list(
          selector = selector,
          class = cls
        )
      )
    })
  }
  if (length(remove_class)) {
    remove_class <- trimws(unlist(strsplit(remove_class, " ")))
    remove_class <- remove_class[!remove_class %in% "shidashi-output-status"]
    lapply(remove_class, function(cls) {
      session$sendCustomMessage(
        "shidashi.remove_class",
        message = list(
          selector = selector,
          class = cls
        )
      )
    })
  }
  invisible()
}






