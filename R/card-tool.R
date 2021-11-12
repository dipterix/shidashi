#' @title Generates small icon widgets
#' @description The icons cane be displayed at header line within
#' \code{\link{accordion}}, \code{\link{card}}, \code{\link{card2}},
#' \code{\link{card_tabset}}. See their examples.
#' @param inputId the button id, only necessary when \code{widget}
#' is \code{"custom"}
#' @param title the tip message to show when the mouse cursor hovers
#' on the icon
#' @param widget the icon widget type; choices are \code{"maximize"},
#' \code{"collapse"}, \code{"remove"}, \code{"flip"},
#' \code{"refresh"}, \code{"link"}, and \code{"custom"}; see 'Details'
#' @param icon icon to use if you are unsatisfied with the default ones
#' @param class additional class for the tool icons
#' @param href,target used when \code{widget} is \code{"link"}, will
#' open an external website; default is open a new tab
#' @param start_collapsed used when \code{widget} is \code{"collapse"},
#' whether the card should start collapsed
#' @param ... passed to the tag as attributes
#' @return 'HTML' tags to be included in \code{tools} parameter in
#' \code{\link{accordion}}, \code{\link{card}}, \code{\link{card2}},
#' \code{\link{card_tabset}}
#' @details There are 7 \code{widget} types:
#' \describe{
#' \item{\code{"maximize"}}{allow the elements to maximize
#' themselves to full-screen}
#' \item{\code{"collapse"}}{allow the elements to collapse}
#' \item{\code{"remove"}}{remove a \code{\link{card}} or
#' \code{\link{card2}}}
#' \item{\code{"flip"}}{used together with \code{\link{flip_box}},
#' to allow card body to flip over}
#' \item{\code{"refresh"}}{refresh all shiny outputs}
#' \item{\code{"link"}}{open a hyper-link pointing to external
#' websites}
#' \item{\code{"custom"}}{turn the icon into a \code{actionButton}.
#' in this case, \code{inputId} must be specified.}
#' }
#' @export
card_tool <- function(inputId = NULL, title = NULL, widget = c("maximize", "collapse", "remove", "flip", "refresh", "link", "custom"), icon, class = "", href = "#", target = "_blank", start_collapsed = FALSE, ...){
  widget <- match.arg(widget)

  if(missing(icon)){
    icon <- switch (
      widget,
      maximize = as_icon("expand"),
      collapse = as_icon(ifelse(start_collapsed, "plus", "minus")),
      remove = as_icon("times"),
      refresh = as_icon("sync-alt"),
      link = as_icon("external-link-alt"),
      flip = as_icon('adjust'),
      {
        stop("Custom widget must provide a valid icon; see ?shiny::icon")
      }
    )
  } else {
    icon <- as_icon(icon)
  }

  if(length(inputId) == 1){
    class <- combine_class("btn btn-tool action-button", class)
  } else {
    class <- combine_class("btn btn-tool", class)
  }

  if( widget == "custom" ){
    widget <- NULL
  }

  if(startsWith(href, "#")){
    target <- "_self"
  }

  return(shiny::a(
    id = inputId,
    type="button",
    href = href,
    target = target,
    class=class,
    `data-card-widget` = widget,
    title = title,
    icon,
    ...
  ))

}
