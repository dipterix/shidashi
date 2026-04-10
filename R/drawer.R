#' @name drawer
#' @title Open, close, or toggle the drawer panel
#' @description Send messages to the client to open, close, or toggle the
#' off-canvas drawer panel on the right side of the dashboard.
#' @param session shiny session
#' @return No value is returned (called for side effect).
#'
#' @examples
#' server <- function(input, output, session) {
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
drawer_open <- function(session = shiny::getDefaultReactiveDomain()) {
  session$sendCustomMessage("shidashi.drawer_open", list())
}

#' @rdname drawer
#' @export
drawer_close <- function(session = shiny::getDefaultReactiveDomain()) {
  session$sendCustomMessage("shidashi.drawer_close", list())
}

#' @rdname drawer
#' @export
drawer_toggle <- function(session = shiny::getDefaultReactiveDomain()) {
  session$sendCustomMessage("shidashi.drawer_toggle", list())
}


#' Drawer shell for module templates
#'
#' @description
#' Emits a minimal \code{.shidashi-drawer} container with a
#' \code{\link[shiny]{uiOutput}} placeholder inside, plus the drawer
#' overlay.  The drawer starts empty; module server code fills it
#' dynamically via \code{shiny::renderUI}.
#'
#' Typical usage in a \file{module-ui.html} template:
#' \preformatted{
#'   \{\{ shidashi::module_drawer() \}\}
#' }
#'
#' Then in the module server:
#' \preformatted{
#'   output$shidashi_drawer <- shiny::renderUI(\{
#'     shiny::tagList(
#'       shiny::h5("My settings"),
#'       shiny::p("Custom drawer content here.")
#'     )
#'   \})
#' }
#'
#' The \code{ns()} function from the module's template evaluation
#' environment is used automatically so that the output ID is
#' properly scoped to the module namespace.
#'
#' @param output_id character; the output ID for the
#'   \code{uiOutput} placeholder inside the drawer.
#'   Defaults to \code{"shidashi_drawer"}.
#' @return A \code{shiny::tagList} containing the drawer div and
#'   its overlay.
#' @export
module_drawer <- function(output_id = "shidashi_drawer") {
  # Resolve the module's ns() from the template evaluation env
  ns_func <- tryCatch(
    get("ns", envir = parent.frame()),
    error = function(e) identity
  )

  shiny::tagList(
    shiny::div(
      class = "shidashi-drawer",
      shiny::div(
        class = "shidashi-drawer-close-tab",
        shiny::tags$i(class = "fas fa-xmark")
      ),
      shiny::div(
        class = "shidashi-drawer-content",
        shiny::uiOutput(ns_func(output_id))
      )
    ),
    shiny::div(class = "shidashi-drawer-overlay")
  )
}
