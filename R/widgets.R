
#' @export
flex_container <- function(
  ...,
  style = NULL,
  direction = c("row", "column"),
  wrap = c("wrap", "nowrap", "wrap-reverse"),
  justify = c("flex-start", "center", "flex-end", "space-around", "space-between"),
  align_box = c("stretch", "flex-start", "center", "flex-end", "baseline"),
  align_content = c("stretch", "flex-start", "flex-end", "space-between", "space-around", "center")
){
  call <- match.call(expand.dots = FALSE)
  style1 <- style
  style <- list()

  if(length(call[['direction']])){
    direction <- match.arg(direction)
    style[["flex-direction"]] <- direction
  }

  if(length(call[['wrap']])){
    wrap <- match.arg(wrap)
    style[["flex-wrap"]] <- wrap
  }

  if(length(call[['justify']])){
    justify <- match.arg(justify)
    style[["justify-content"]] <- justify
  }

  if(length(call[['align_box']])){
    align_box <- match.arg(align_box)
    style[["align-content"]] <- align_box
  }

  if(length(call[['align_content']])){
    align_content <- match.arg(align_content)
    style[["align-items"]] <- align_content
  }

  style$display <- "flex"
  style <- paste(names(style), as.vector(style), sep = ":", collapse = "; ")
  if(length(style1)){
    style <- paste0(style, ";", style1)
  }


  shiny::div(style = style, ...)
}


#' @export
flex_item <- function(
  ..., style = NULL, order = NULL, flex = "1",
  align = c("flex-start", "flex-end", "center")
){
  l <- list()
  if(length(align) == 1){
    align <- match.arg(align)
    l[["align-self"]] <- align
  }
  l[['order']] <- order
  l[['flex']] <- flex

  style1 <- paste(names(l), as.vector(l), sep = ":", collapse = "; ")
  if(length(style)){
    style1 <- paste0(style1, "; ", style)
  }


  shiny::div(
    ...,
    style = style1
  )

}

#' @export
back_top_button <- function(icon = "chevron-up"){
  shiny::a(
    href = "#",
    class = "btn btn-info back-to-top",
    role = "button",
    `aria-label`="Scroll to top",
    as_icon(icon)
  )
}

