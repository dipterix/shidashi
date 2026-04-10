# UI: a single full-size output container.
# The output type (plot vs htmlwidget) is determined at runtime
# by server_standalone_viewer() based on the original render function.
viewer_output <- function() {
  shiny::uiOutput(ns("viewer_content"), class = "fill-width", style = "width:100%;height:100%;")
}
