#' @export
progressOutput <- function(
  outputId, width = "100%",
  description = "Initializing", class = "bg-primary"
){

  shiny::div(
    class = "shinytemplates-progress-output",
    id = outputId,
    style = sprintf("width: %s;", width),
    shiny::div(
      class = "progress",
      shiny::div(
        class = combine_class("progress-bar", class),
        style = "width: 0%",
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
    value <- as.integer(value)
    if( value < 0 ){ value <- 0 }
    if( value > 100 ){ value <- 100 }
    list(
      value = value,
      description = description
    )

  }, progressOutput, outputArgs)

}

#' @export
clipboardOutput <- function(
  outputId = rand_string(), message = "Copy to clipboard",
  clip_text = "", class = NULL, as_card_tool = FALSE){

  if(as_card_tool){
    card_tool(
      class = combine_class('clipboard-btn', "shinytemplates-clipboard-output", class),
      icon = "copy",
      title = message,
      inputId = outputId,
      widget = "custom",
      "data-clipboard-text" = clip_text
    )
  } else {
    shiny::div(
      id = outputId,
      class = "shinytemplates-clipboard-output",
      shiny::tags$button(
        class = combine_class('clipboard-btn btn btn-default', class),
        "data-clipboard-text" = clip_text,
        role = 'button',
        message
      )
    )
  }

}


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
