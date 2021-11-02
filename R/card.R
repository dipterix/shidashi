
#' @export
card <- function(
  title, ..., footer = NULL, tools = NULL, inputId = NULL,
  class = "card-dark", class_header = "", class_body = "",
  style_header = NULL, style_body = NULL, start_collapsed = FALSE,
  root_path = template_root()){

  body <- shiny::tagList(...)

  template_path <- file.path(root_path, 'views', 'card.html')

  if(length(footer)){
    footer <- shiny::div(
      class = "card-footer",
      footer
    )
  } else {
    footer = ''
  }

  if(length(tools)){
    tools <- shiny::div(
      class = "card-tools",
      tools
    )
  } else {
    tools = ""
  }

  if(length(inputId) == 1){
    if(grepl("[\"']", inputId)){
      stop("`card` ID cannot contain quotation marks.")
    }
    card_id <- sprintf(" id='%s'", inputId)
  } else {
    card_id <- ''
  }

  shiny::htmlTemplate(
    template_path,
    document_ = FALSE,
    title = title,
    body = body,
    class = class,
    class_header = class_header,
    class_body = class_body,
    style_header = style_header,
    style_body = style_body,
    footer = footer,
    tools = tools,
    card_id = card_id,
    start_collapsed = start_collapsed
  )
}

#' @export
card2 <- function(
  title, body_main, body_side = NULL,
  footer = NULL, tools = NULL, inputId = NULL,
  class = "card-dark", class_header = "", class_body = "",
  style_header = NULL, style_body = NULL, start_collapsed = FALSE,
  root_path = template_root()){

  template_path <- file.path(root_path, 'views', 'card2.html')

  if(length(footer)){
    footer <- shiny::div(
      class = "card-footer",
      footer
    )
  } else {
    footer = ''
  }

  if(length(tools)){
    tools <- shiny::tagList(
      tools
    )
  } else {
    tools = ""
  }

  if(length(inputId) == 1){
    if(grepl("[\"']", inputId)){
      stop("`card` ID cannot contain quotation marks.")
    }
    card_id <- sprintf(" id='%s'", inputId)
  } else {
    card_id <- ''
  }

  shiny::htmlTemplate(
    template_path,
    document_ = FALSE,
    title = title,
    body_main = body_main,
    body_side = body_side,
    class = class,
    class_header = class_header,
    class_body = class_body,
    style_header = style_header,
    style_body = style_body,
    footer = footer,
    tools = tools,
    card_id = card_id,
    start_collapsed = start_collapsed
  )
}
