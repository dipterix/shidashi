#' @name drawer
#' @title Open, close, or toggle the drawer panel
#' @description Send messages to the client to open, close, or toggle the
#' off-canvas drawer panel on the right side of the dashboard.
#' @param session shiny session
#' @return No value is returned (called for side effect).
#'
#' @examples
#' server <- function(input, output, session){
#'   # Open the drawer
#'   drawer_open()
#'
#'   # Close the drawer
#'   drawer_close()
#'
#'   # Toggle the drawer
#'   drawer_toggle()
#' }
#'
#' @export
drawer_open <- function(session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage("shidashi.drawer_open", list())
}

#' @rdname drawer
#' @export
drawer_close <- function(session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage("shidashi.drawer_close", list())
}

#' @rdname drawer
#' @export
drawer_toggle <- function(session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage("shidashi.drawer_toggle", list())
}
