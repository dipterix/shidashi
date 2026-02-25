library(shiny)
library(shidashi)

ui_use_template <- function(){
  column(
    width = 12,
    h2("Start with a default template", class = "shidashi-anchor"),
    div(
      tags$ul(
        tags$li(
          span(
            class = "inline-all",
            "Start your ", tags$code("RStudio"), ", click on the ", tags$code("File"),
            " menu, choose ", tags$code("New Project...")
          )
        ),
        tags$li(
          span(
            class = "inline-all",
            "In the project wizard, ",
            "choose ", tags$code("New Directory")
          )
        ),
        tags$li(
          span(
            class = "inline-all",
            "Find and select ",
            tags$code("Shidashi Shiny Template")
          )
        ),
        tags$li(
          span(
            class = "inline-all",
            "Enter your project name, ",
            "as well as the project directory. ",
            "Please accept the default user & theme"
          )
        ),
        tags$li(
          span(
            class = "inline-all",
            "Click on ",
            tags$code("Create Project"), ", ",
            tags$code("RStudio"),
            " will create a ", tags$code("shidashi"),
            " project containing this demo."
          )
        )
      )
    )
  )
}
