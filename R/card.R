
#' @export
card <- function(
  title, ..., footer = NULL, tools = NULL, inputId = NULL,
  class = "", class_header = "", class_body = "", class_foot = "",
  style_header = NULL, style_body = NULL, start_collapsed = FALSE,
  resizable = FALSE, root_path = template_root()){

  call <- match.call()
  body <- shiny::tagList(...)

  template_path <- file.path(root_path, 'views', 'card.html')

  if(length(footer)){
    footer <- shiny::div(
      class = paste(c("card-footer", class_foot), collapse = " "),
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

  if(resizable){
    class_body <- paste(c(
      "height-400 resize-vertical flex-container no-padding",
      class_body
    ), collapse = " ")
    body <- flex_item(
      class = "fill-height fill-width",
      body
    )
  } else {
    class_body <- paste(c(
      "fill-width fill-height",
      class_body
    ), collapse = " ")
  }

  set_attr_call(shiny::htmlTemplate(
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
  ), call)
}

#' @export
card2 <- function(
  title, body_main, body_side = NULL,
  footer = NULL, tools = NULL, inputId = NULL,
  class = "", class_header = "", class_body = "min-height-400",
  class_foot = "",
  style_header = NULL, style_body = NULL, start_collapsed = FALSE,
  root_path = template_root()){

  call <- match.call()
  template_path <- file.path(root_path, 'views', 'card2.html')

  if(length(footer)){
    footer <- shiny::div(
      class = paste(c("card-footer", class_foot), collapse = " "),
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

  set_attr_call(shiny::htmlTemplate(
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
  ), call)
}


#' @export
card2_open <- function(inputId, session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage(
    "shinytemplates.card2widget",
    list(
      selector = sprintf("#%s:not(.direct-chat-contacts-open) .card-tools>.btn-tool.card2-switch", session$ns(inputId))
    )
  )
}

#' @export
card2_close <- function(inputId, session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage(
    "shinytemplates.card2widget",
    list(
      selector = sprintf("#%s.direct-chat-contacts-open .card-tools>.btn-tool.card2-switch", session$ns(inputId))
    )
  )
}

#' @export
card2_toggle <- function(inputId, session = shiny::getDefaultReactiveDomain()){
  # session$sendCustomMessage(
  #   "shinytemplates.click",
  #   list(
  #     selector = sprintf("#%s .card-tools>.btn-tool.card2-switch", session$ns(inputId))
  #   )
  # )
  session$sendCustomMessage(
    "shinytemplates.card2widget",
    list(
      selector = sprintf("#%s .card-tools>.btn-tool.card2-switch", session$ns(inputId))
    )
  )
}


#' @export
card_operate <- function(
  inputId, method, session = shiny::getDefaultReactiveDomain()
){
  method <- match.arg(
    method, choices = c("collapse", "expand", "remove", "toggle",
                        "maximize", "minimize", "toggleMaximize")
  )
  session$sendCustomMessage(
    "shinytemplates.cardwidget",
    list(
      inputId = session$ns(inputId),
      method = method
    )
  )
}

