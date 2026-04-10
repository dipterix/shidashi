library(shiny)
library(shidashi)

server <- function(input, output, session, ...) {
  server_session_events(input, output, session, ...)
}
