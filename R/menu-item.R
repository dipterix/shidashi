
#' @export
as_icon <- function(icon = NULL, class = "fas"){
  class <- combine_class(class)

  if(is.null(icon)){
    icon <- ""
  } else {
    if(inherits(icon, "shiny.tag")) {
      icon$attribs$class <- combine_class(icon$attribs$class, class)
    } else {
      icon <- shiny::icon(icon, class = class)
    }
    # remove class fa
    if ( class != "fa" ){
      remove_class(icon$attribs$class, "fa")
    }
  }


  icon
}

 #' @export
as_badge <- function(badge = NULL){
  if(is.null(badge) || nchar(badge) == 0){
    badge <- ''
  } else {
    if(inherits(badge, "shiny.tag")) {
      badge$attribs$class <- c(badge$attribs$class, " right badge")
    } else {
      badge <- strsplit(badge, "\\|")[[1]]
      if(length(badge) > 1){
        badge <- shiny::span(class=paste("right badge", badge[[2]]), badge[[1]])
      } else {
        badge <- shiny::span(class=paste("right badge"), badge[[1]])
      }
    }
  }
  badge
}

#' @export
menu_item <- function(
  text, href = "#", icon = NULL, active = FALSE, badge = NULL,
  target = "_blank", root_path = template_root()){

  icon <- as_icon(icon, class = "nav-icon fas")
  badge <- as_badge(badge)
  module <- ''
  if(startsWith(href, "#")){
    target <- "_self"
  } else if (startsWith(href, "/?module=")) {
    query_list <- httr::parse_url(href)
    query_list$query
    module <- query_list$query$module
    module <- gsub(pattern = " ", replacement = "", module)
    if( grepl("[^a-zA-Z0-9_]", module) ){
      stop("Function `menu_item`: for `href` with module link (starts with '/?module=<ID>'), the module `ID` can only contain letters, digits, and/or '_'.")
    }
  }
  template_path <- file.path(root_path, "views", "menu-item.html")
  # if(!file.exists(template_path)){
  #   template_path <- system.file('snippets', 'menu-item.html', package = 'shidashi')
  # }
  shiny::htmlTemplate(
    template_path,
    document_ = FALSE,
    text = text, href = shiny::HTML(href), icon = icon, badge = badge, active = active,
    target = target, module = module)
}

#' @export
menu_item_dropdown <- function(
  text, ..., .list = NULL, icon = NULL, active = FALSE,
  badge = NULL, root_path = template_root()){

  sub_items <- c(shiny::tagList(...), .list)
  icon <- as_icon(icon, class = "nav-icon fas")
  badge <- as_badge(badge)
  template_path <- file.path(root_path, "views", "menu-item-dropdown.html")
  # if(!file.exists(template_path)){
  #   template_path <- system.file('snippets', 'menu-item-dropdown.html', package = 'shidashi')
  # }
  shiny::htmlTemplate(
    template_path,
    document_ = FALSE,
    text = text, icon = icon, badge = badge,
    active = active, sub_items = sub_items)
}
