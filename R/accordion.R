
#' @export
accordion_item <- function(
  title, ..., footer = NULL, tools = NULL,
  class = "", collapsed = TRUE,
  parentId = rand_string(), itemId = rand_string(),
  style_header = NULL, style_body = NULL,
  root_path = template_root()){

  body <- shiny::tagList(...)

  template_path <- file.path(root_path, 'views', 'accordion-item.html')

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
      class = "card-tools card-accordion",
      tools
    )
  } else {
    tools = ""
  }

  shiny::htmlTemplate(
    template_path,
    document_ = FALSE,
    title = title,
    body = body,
    class = class,
    parentId = parentId,
    itemId = itemId,
    style_header = style_header,
    style_body = style_body,
    footer = footer,
    tools = tools,
    collapsed = collapsed
  )
}

#' @export
accordion <- function(
  ..., id = rand_string(),
  class = NULL, style_header = NULL,
  style_body = NULL, env = parent.frame(), extras = list(),
  root_path = template_root()){

  call <- match.call(expand.dots = FALSE)

  force(root_path)
  parentId <- id

  items <- unname(lapply(call[['...']], function(item){
    item[["parentId"]] <- parentId
    item[["root_path"]] <- root_path

    if(!is.null(class)){
      item[["class"]] <- class
    }

    if(!is.null(style_header)){
      item[["style_header"]] <- style_header
    }
    if(!is.null(style_body)){
      item[["style_body"]] <- style_body
    }
    eval(item, envir = env)
  }))

  extras <- as.list(extras)
  extras$id <- parentId
  extras <- c(extras, items)

  do.call(shiny::div, extras)

}
