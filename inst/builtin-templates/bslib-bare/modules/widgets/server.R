library(shiny)
library(shidashi)

server <- function(input, output, session, ...){

  server_notification(input, output, session, ...)
  server_progress(input, output, session, ...)
  server_info_box(input, output, session, ...)
  server_flip_box(input, output, session, ...)
  server_accordion(input, output, session, ...)

}
