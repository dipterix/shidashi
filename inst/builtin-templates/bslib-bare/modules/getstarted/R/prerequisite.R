library(shiny)
library(shidashi)

ui_prerequisite <- function() {
  column(
    width = 7L,
    h2("Pre-requisite for this tutorial", class = "shidashi-anchor"),
    p(
      span(
        class = "inline-all",
        "I believe you have had `shidashi` installed. ",
        "However, this tutorial requires some extra packages. ",
        "Please run the following R command:"
      )
    ),
    html_highlight_code(
      install.packages(c("ggExtra", "rmarkdown")),
      hover = "overflow-auto"
    ),
    tags$small(
      "* You can click the code to copy the code."
    )
  )
}
