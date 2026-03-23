library(shiny)
library(shidashi)

server <- function(input, output, session, ...){
  server_aiagent(input, output, session, ...)
}
