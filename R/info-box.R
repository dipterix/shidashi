
#' Generates 'HTML' info box
#' @param ... box content
#' @param icon the box icon; default is \code{"envelope"}, can be hidden by
#' specifying \code{NULL}
#' @param class class of the box container
#' @param class_icon class of the icon
#' @param class_content class of the box body
#' @param root_path see \code{\link{template_root}}
#' @return 'HTML' tags
#' @examples
#'
#' library(shiny)
#' library(shidashi)
#'
#' info_box("Message", icon = "cogs")
#'
#' info_box(
#'   icon = "thumbs-up",
#'   span(class = "info-box-text", "Likes"),
#'   span(class = "info-box-number", "12,320"),
#'   class_icon = "bg-red"
#' )
#'
#' info_box("No icons", icon = NULL)
#'
#' @export
info_box <- function(..., icon = "envelope", class = "",
                     class_icon = "bg-info", class_content = "",
                     root_path = template_root()) {
  call <- match.call(expand.dots = TRUE)
  if(length(icon)){
    icon <- shiny::span(
      class = combine_class("info-box-icon", class_icon),
      as_icon(icon)
    )
  }

  template_path <- file.path(root_path, 'views', 'info-box.html')

  re <- shiny::htmlTemplate(
    template_path,
    document_ = FALSE,
    icon = icon,
    body = shiny::tagList(...),
    class = combine_class(class),
    class_content = combine_class(class_content)
  )

  set_attr_call(re, call)
}

#' @title An 'HTML' container that can flip
#' @param inputId element 'HTML' id; must be specified if \code{active_on} is
#' not \code{'click'}
#' @param front 'HTML' elements to show in the front
#' @param back 'HTML' elements to show when the box is flipped
#' @param active_on the condition when a box should be flipped; choices are
#' \code{'click'}: flip when double-click on both sides; \code{'click-front'}:
#' only flip when the front face is double-clicked; \code{'manual'}: manually
#' flip in \code{R} code (see \code{{flip(inputId)}} function)
#' @param session shiny session; default is current active domain
#' @param class 'HTML' class
#' @return \code{flip_box} returns 'HTML' tags; \code{flip} should be called
#' from shiny session, and returns nothing
#' @examples
#'
#' # More examples are available in demo
#'
#' library(shiny)
#' library(shidashi)
#'
#' session <- MockShinySession$new()
#'
#' flip_box(front = info_box("Side A"),
#'          back = info_box("Side B"),
#'          inputId = 'flip_box1')
#'
#' flip('flip_box1', session = session)
#'
#' @export
flip_box <- function(front, back, active_on = c("click", "click-front", "manual"), inputId = NULL, class = NULL){
  call <- match.call()
  active_on <- match.arg(active_on)
  if(active_on != 'click' && length(inputId) != 1){
    stop("`inputId` must be specified if `active_on` is not 'click'")
  }
  set_attr_call(shiny::div(
    class = combine_class("flip-box", class),
    "data-toggle" = active_on,
    id = inputId,
    shiny::div(
      class = "flip-box-inner",
      shiny::div(
        class = "flip-box-back",
        back
      ),
      shiny::div(
        class = "flip-box-front",
        front
      )
    )
  ), call)
}

#' @rdname flip_box
#' @export
flip <- function(inputId, session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage("shidashi.box_flip", list(
    inputId = session$ns(inputId)
  ))
}
