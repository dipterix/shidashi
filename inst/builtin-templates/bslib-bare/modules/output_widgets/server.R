library(shiny)
library(shidashi)

server <- function(input, output, session, ...) {

  server_base_plot(input, output, session, ...)
  server_ggplot_brush(input, output, session, ...)
  server_threebrain(input, output, session, ...)

}
