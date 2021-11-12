#' @name notification
#' @title The 'Bootstrap' notification
#' @param message notification body content, can be 'HTML' tags
#' @param title,subtitle title and subtitle of the notification
#' @param type type of the notification; can be \code{"default"},
#' \code{"info"}, \code{"warning"}, \code{"success"}, \code{"danger"},
#' \code{"white"}, \code{"dark"}
#' @param close whether to allow users to close the notification
#' @param position where the notification should be; choices are
#' \code{"topRight"}, \code{"topLeft"}, \code{"bottomRight"},
#' \code{"bottomLeft"}
#' @param autohide whether to automatically hide the notification
#' @param fixed whether the position should be fixed
#' @param delay integer in millisecond to hide the notification if
#' \code{autohide=TRUE}
#' @param icon the icon of the title
#' @param collapse if \code{message} is a character vector, the collapse string
#' @param session shiny session domain
#' @param class the extra class of the notification, can be used for style
#' purposes, or by \code{clear_notifications} to close specific notification
#' types.
#' @param ... other options; see
#' \url{https://adminlte.io/docs/3.1//javascript/toasts.html#options}
#'
#' @examples
#' \dontrun{
#'
#' # the examples must run in shiny reactive context
#'
#' show_notification(
#'   message = "This validation process has finished. You are welcome to proceed.",
#'   autohide = FALSE,
#'   title = "Success!",
#'   subtitle = "type='success'",
#'   type = "success"
#' )
#'
#' show_notification(
#'   message = "This notification has title and subtitle",
#'   autohide = FALSE,
#'   title = "Hi there!",
#'   subtitle = "Welcome!",
#'   icon = "kiwi-bird",
#'   class = "notification-auto"
#' )
#'
#' # only clear notifications with class "notification-auto"
#' clear_notifications("notification-auto")
#'
#' }
NULL

#' @rdname notification
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

#' @rdname notification
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



