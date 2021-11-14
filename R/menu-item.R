
#' Convert characters, shiny icons into 'fontawesome' 4
#' @param icon character or \code{\link[shiny]{icon}}
#' @param class icon class; change this when you are using 'fontawesome'
#' professional version. The choices are \code{'fa'} (compatible),
#' \code{'fas'} (strong), \code{'far'} (regular), \code{'fal'} (light),
#' and \code{'fad'} (duo-tone).
#' @return 'HTML' tag
#' @examples
#'
#' as_icon("bookmark", class = "far")
#' as_icon("bookmark", class = "fas")
#'
#' # no icon
#' as_icon(NULL)
#'
#' @export
as_icon <- function(icon = NULL, class = "fas"){
  class <- combine_class(class)

  if(is.null(icon) || icon == ""){
    icon <- ""
  } else {
    if(inherits(icon, "shiny.tag")) {
      icon$attribs$class <- combine_class(icon$attribs$class, class)
    } else {
      icon <- shiny::icon(icon, class = class)
    }
    # remove class fa
    if ( !"fa" %in% class ){
      icon$attribs$class <- remove_class(icon$attribs$class, "fa")
    }
  }


  icon
}

#' @title Generates badge icons
#' @description Usually used along with \code{\link{card}},
#' \code{\link{card2}}, and \code{\link{card_tabset}}. See \code{tools}
#' parameters in these functions accordingly.
#' @param badge characters, \code{"shiny.tag"} object or \code{NULL}
#' @return 'HTML' tags
#' @details When \code{badge} is \code{NULL} or empty, then \code{as_badge}
#' returns empty strings. When \code{badge} is a \code{"shiny.tag"} object,
#' then 'HTML' class \code{'right'} and \code{'badge'} will be appended.
#' When \code{badge} is a string, it should follow the syntax of
#' \code{"message|class"}. The text before \code{"|"} will be the badge
#' message, and the text after the \code{"|"} becomes the class string.
#' @examples
#'
#' # Basic usage
#' as_badge("New")
#'
#' # Add class `bg-red` and `no-padding`
#' as_badge("New|bg-red no-padding")
#'
#'
#' @export
as_badge <- function(badge = NULL){
  if(!length(badge) || nchar(badge) == 0){
    badge <- ''
  } else {
    if(inherits(badge, "shiny.tag")) {
      badge$attribs$class <- combine_class(badge$attribs$class, "right badge")
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
