

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


#' @export
flip_box <- function(front, back, active_on = c("click", "click-front", "manual"), inputId = NULL){
  call <- match.call()
  active_on <- match.arg(active_on)
  if(active_on != 'click' && length(inputId) != 1){
    stop("`inputId` must be specified if `active_on` is not 'click'")
  }
  set_attr_call(shiny::div(
    class = "flip-box",
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

#' @export
flip <- function(inputId, session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage("shidashi.box_flip", list(
    inputId = session$ns(inputId)
  ))
}
