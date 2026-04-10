library(shiny)
library(shidashi)

server <- function(input, output, session, ...) {
  server_stream_viz(input, output, session, ...)
}
