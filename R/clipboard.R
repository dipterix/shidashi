#' @title Generates outputs that can be written to clipboards with one click
#' @param outputId the output id
#' @param message tool tip to show when mouse hovers on the element
#' @param clip_text the initial text to copy to clipboards
#' @param class 'HTML' class of the element
#' @param as_card_tool whether to make the output as \code{\link{card_tool}}
#' @param expr expression to evaluate; the results will replace
#' \code{clip_text}
#' @param env environment to evaluate \code{expr}
#' @param quoted whether \code{expr} is quoted
#' @param outputArgs used to replace default arguments of \code{clipboardOutput}
#' @return 'HTML' elements that can write to clip-board once users click on
#' them.
#' @examples
#' clipboardOutput(clip_text = "Hey there")
#'
#' @export
clipboardOutput <- function(
  outputId = rand_string(prefix = "clipboard"), message = "Copy to clipboard",
  clip_text = "", class = NULL, as_card_tool = FALSE){

  if(as_card_tool){
    card_tool(
      class = combine_class('clipboard-btn', "shidashi-clipboard-output", class),
      icon = "copy",
      title = message,
      inputId = outputId,
      widget = "custom",
      "data-clipboard-text" = clip_text
    )
  } else {
    shiny::div(
      id = outputId,
      class = "shidashi-clipboard-output",
      shiny::tags$button(
        class = combine_class('clipboard-btn btn btn-default', class),
        "data-clipboard-text" = clip_text,
        role = 'button',
        message
      )
    )
  }

}

#' @rdname clipboardOutput
#' @export
renderClipboard <- function(expr, env=parent.frame(), quoted=FALSE, outputArgs = list()) {

  func <- shiny::installExprFunction(expr, "func", env, quoted, label = "renderClipboard")
  shiny::createRenderFunction(func, function(value, session, name, ...) {

    if(!is.character(value)) {
      value <- deparse(value)
    }
    if(length(value) > 1){
      value <- paste(value, collapse = "\n")
    }
    value

  }, clipboardOutput, outputArgs)

}

