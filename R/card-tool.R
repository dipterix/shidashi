
#' @export
card_tool <- function(inputId = NULL, title = NULL, widget = c("maximize", "collapse", "remove", "refresh", "link", "custom"), icon, class = "", href = "#", target = "_blank", start_collapsed = FALSE, ...){
  widget <- match.arg(widget)

  if(missing(icon)){
    icon <- switch (
      widget,
      maximize = shiny::icon("expand"),
      collapse = shiny::icon(ifelse(start_collapsed, "plus", "minus")),
      remove = shiny::icon("times"),
      refresh = shiny::icon("sync-alt"),
      link = shiny::icon("external-link-alt"),
      {
        stop("Custom widget must provide a valid icon; see ?shiny::icon")
      }
    )
  }
  icon <- as_icon(icon)

  if(length(inputId) == 1){
    class <- paste("btn btn-tool action-button", paste(class, collapse = " "))
  } else {
    class <- paste("btn btn-tool", paste(class, collapse = " "))
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
