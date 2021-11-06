

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
