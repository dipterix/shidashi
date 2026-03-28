library(shiny)
library(shidashi)

# Controls card — simulate button + parameter sliders
ui_stream_viz_controls <- function() {
  shidashi::card(
    title = "Simulate Signal",
    tools = list(
      shidashi::card_tool(widget = "collapse")
    ),
    fluidRow(
      column(
        width = 3L,
        sliderInput(
          inputId = ns("n_channels"),
          label = "Channels",
          min = 1L, max = 64L, value = 10L, step = 1L
        )
      ),
      column(
        width = 3L,
        sliderInput(
          inputId = ns("n_seconds"),
          label = "Duration (s)",
          min = 1L, max = 30L, value = 5L, step = 1L
        )
      ),
      column(
        width = 3L,
        sliderInput(
          inputId = ns("sample_rate"),
          label = "Sample rate (Hz)",
          min = 100L, max = 2000L, value = 500L, step = 100L
        )
      ),
      column(
        width = 3L,
        br(),
        actionButton(
          inputId = ns("btn_simulate"),
          label = "Simulate",
          icon = shidashi::as_icon("play"),
          class = "btn btn-primary w-100"
        )
      )
    )
  )
}

# Viewer card — hosts the streamVizOutput widget
ui_stream_viz_plot <- function() {
  shidashi::card(
    title = "Signal Viewer",
    resizable = TRUE,
    tools = list(
      shidashi::card_tool(widget = "collapse"),
      shidashi::card_tool(widget = "maximize")
    ),

    shidashi::streamVizOutput(ns("viz_signal"), height = "100%")
  )
}
