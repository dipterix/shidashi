library(shiny)
library(shidashi)

server <- function(input, output, session, ...){

  shared_data <- shidashi::register_session_id(session)

  server_demo(input, output, session, ...)
}
