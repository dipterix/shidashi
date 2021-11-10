#' @export
show_notification <- function(
  message,
  title = "Notification!",
  subtitle = "",
  type = c("default", "info", "warning", "success", "danger", "white", "dark"),
  close = TRUE,
  position = c("topRight", "topLeft", "bottomRight", "bottomLeft"),
  autohide = TRUE,
  fixed = TRUE,
  delay = 5000,
  icon = NULL,
  collapse = "",
  session = shiny::getDefaultReactiveDomain(),
  class = NULL,
  ...
){
  type <- match.arg(type)
  position <- match.arg(position)
  delay <- as.integer(delay)
  if(!length(delay) || is.na(delay) || delay <= 0){
    delay <- 5000L
    close <- TRUE
  }
  if(length(icon)){
    icon <- as_icon(icon)
    icon <- icon$attribs$class
  }
  message <- paste(message, collapse = "")

  session$sendCustomMessage("shidashi.show_notification", list(
    position = position,
    autohide = !isFALSE(autohide),
    delay = delay,
    icon = icon,
    title = title,
    subtitle = subtitle,
    close = !isFALSE(close),
    body = message,
    fixed = !isFALSE(fixed),
    class = combine_class(sprintf("bg-%s", type), class),
    ...
  ))

}

#' @export
clear_notifications <- function(
  class = NULL,
  session = shiny::getDefaultReactiveDomain()){

  class <- unique(c(class, "toast"))
  class <- gsub(" ", "", class)
  class <- class[class != ""]
  selector <- paste0(".", class, collapse = "")
  session$sendCustomMessage("shidashi.clear_notification", list(
    selector = selector
  ))
}



