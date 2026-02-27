library(shiny)
library(shidashi)

ui_render <- function(){
  column(
    width = 12L,
    h2("Render your first project", class = "shidashi-anchor"),
    p(
      span(
        class = "inline-all",
        "Once you start a new shidashi project, a ",
        tags$code("start.R"), " file will be created with three lines:"
      )
    ),
    fluidRow(
      column(
        6L,
        tags$pre(
          class = 'no-padding bg-gray-90 pre-compact',
          tags$code(
            class = "r",
            'library(shidashi)

# Set root path to your project folder
shidashi::template_settings$set(root_path = \'<your project folder>\')

# Render project
shidashi::render(host = \'127.0.0.1\', port = 8310L)'
          )
        )
      )
    ),
    p(
      span(
        class = "inline-all",
        "The first line loads the shidashi package into your R session. ",
        "The second line sets the ",
        tags$code("root_path"), ", which should be your project path, ",
        "so that shidashi knows where to look at when rendering websites. ",
        "The last line starts a local R-shiny application from port ",
        tags$code("8310"), "."
      )
    )
  )
}

server_demo <- function(input, output, session, ...){
  event_data <- register_session_events(session)
}
