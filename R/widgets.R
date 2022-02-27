#' @title Generate 'HTML' tags with 'flex' layout
#' @param ... for \code{flex_container}, it's elements of \code{flex_item};
#' for \code{flex_item}, \code{...} are shiny 'HTML' tags
#' @param size numerical relative size of the item; will be ignored if
#' \code{flex} is provided
#' @param style the additional 'CSS' style for containers or inner items
#' @param direction,wrap,justify,align_box,align_content 'CSS' styles for
#' 'flex' containers
#' @param order,align,flex CSS' styles for 'flex' items
#' @param class,.class class to add to the elements
#' @return 'HTML' tags
#'
#' @examples
#'
#' x <- flex_container(
#'   style = "position:absolute;height:100vh;top:0;left:0;width:100%",
#'   flex_item(style = 'background-color:black;'),
#'   flex_item(style = 'background-color:red;')
#' )
#' # You can view it via `htmltools::html_print(x)`
#'
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

#' @rdname flex_container
#' @export
flex_item <- function(
  ..., size = 1,
  style = NULL, order = NULL, flex = as.character(size),
  align = c("flex-start", "flex-end", "center"),
  class = NULL,
  .class = "fill-width padding-5"
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

  class <- combine_class(class, .class)

  shiny::div(
    ...,
    style = style1,
    class = class
  )

}

#' @rdname flex_container
#' @export
flex_break <- function(..., class = NULL){
  class <- combine_class(class, "flex-break")
  shiny::div(class = class, ...)
}

#' 'HTML' code to generate small back-to-top button
#' @description This function is a template function that should be called
#' in 'HTML' templates before closing the \code{"</body>"} tag.
#' @param icon the icon for back-to-top button
#' @param title the expanded menu title
#' @return 'HTML' tags
#'
#' @examples
#'
#' back_top_button()
#' back_top_button("rocket")
#'
#' @export
back_top_button <- function(icon = "chevron-up", title = "Jump to"){
  if(!length(title)){
    title <- NULL
  } else {
    title <- shiny::h6(class="dropdown-header", title)
  }
  shiny::div(
    class = "back-to-top",
    shiny::div(
      class = "btn-group dropup",
      role="group",
      shiny::a(
        type="button", class="btn btn-default btn-go-top border-right-1", href="#",
        as_icon(icon)
      ),
      shiny::tags$button(
        type="button",
        class="btn btn-default dropdown-toggle dropdown-toggle-split border-left-1" ,
        "data-toggle"="dropdown",
        "aria-haspopup"="false",
        "aria-expanded"="false",
        shiny::span(
          class = "sr-only",
          "Dropdown-Open"
        )
      ),
      shiny::div(
        class = "dropdown-menu dropdown-menu-right",
        title
      )
    )
  )
}



#' @name add-remove-html-class
#' @title Add or remove 'HTML' class from 'RAVE' application
#' @description Only works in template framework provided by 'shidashi' package,
#' see \code{\link[shidashi]{use_template}}
#' @param selector 'CSS' selector
#' @param class class to add or to remove from selected elements
#' @param session shiny session
#' @return No value is returned
#'
#' @examples
#'
#' server <- function(input, output, session){
#'
#'   # Add class `hidden` to element with ID `elemid`
#'   add_class("#elemid", "hidden")
#'
#'   # Remove class `hidden` from element with class `shiny-input-optional`
#'   remove_class(".shiny-input-optional", "hidden")
#' }
#'
#' @export
add_class <- function(selector, class,
                      session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage("shidashi.add_class", list(
    selector = selector,
    class = class
  ))
}

#' @rdname add-remove-html-class
#' @export
remove_class <- function(selector, class,
                         session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage("shidashi.remove_class", list(
    selector = selector,
    class = class
  ))
}

