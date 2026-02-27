ui_accordion <- function() {

  shiny::fluidRow(
    shiny::column(
      width = 6L,
      shidashi::accordion(
        id = ns("this-accordion"),
        shidashi::accordion_item(
          title = "Step 1",
          collapsed = FALSE,
          footer = shiny::actionLink(
            inputId = ns("accordion_next"),
            label = "Next step"
          ),
          "An accordion is a list of collapsible cards. ",
          "If you expand one of them, the other cards will collapse"
        ),
        shidashi::accordion_item(
          itemId = ns("accordion-step-2"),
          title = list("Step 2", shidashi::as_badge("New|badge-danger")),
          shiny::textInput("input_2", "Input 2"),
          footer = shiny::actionButton(
            inputId = ns("accordion_close"),
            label = "OK, collapse this item"
          ),
          collapsed = TRUE
        )
      )
    ),
    shiny::column(
      width = 6L,
    )
  )

}

server_accordion <- function(input, output, session, ...) {
  shiny::bindEvent(
    shiny::observe({
      shidashi::accordion_operate(
        id = "this-accordion",
        itemId = "accordion-step-2",
        method = "expand"
      )
    }),
    input$accordion_next,
    ignoreInit = TRUE, ignoreNULL = TRUE
  )

  shiny::bindEvent(
    shiny::observe({
      shidashi::accordion_operate(
        id = "this-accordion",
        itemId = "accordion-step-2",
        method = "collapse"
      )
    }),
    input$accordion_close,
    ignoreInit = TRUE, ignoreNULL = TRUE
  )
}
