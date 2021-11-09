
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
