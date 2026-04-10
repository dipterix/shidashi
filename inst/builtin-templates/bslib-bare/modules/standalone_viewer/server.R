server <- function(input, output, session, ...) {

  asNamespace("shidashi")$server_standalone_viewer(input, output, session, ...)
}
