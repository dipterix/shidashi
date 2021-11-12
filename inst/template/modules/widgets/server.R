library(shiny)
library(shidashi)

server <- function(input, output, session, ...){

  shared_data <- shidashi::register_session_id(session)

  server_notification(input, output, session, ...)
  server_progress(input, output, session, ...)
  server_info_box(input, output, session, ...)
  server_flip_box(input, output, session, ...)

}
