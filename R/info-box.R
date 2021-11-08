

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
flip_box <- function(front, back, active_on = c(
  "click", "hover", "manual"
)){
  active_on <- match.arg(active_on)
  shiny::div(
    class = "flip-box",
    "data-toggle" = active_on,
    shiny::div(
      class = "flip-box-inner",
      shiny::div
    )
  )
  <div class="flip-box">
    <div class="flip-box-inner">
    <div class="flip-box-back">
    <h2>Back Side</h2>
    <p>bgbib</p>
    </div>
    <div class="flip-box-front">
    <h2>Front Side</h2>
    </div>
    </div>
    </div>
}
