

ui_card_tools <- function(){
  shiny::tagList(
    shiny::column( width = 3L, card_with_code(
      card(
        class_body = "min-height-400",
        title = "Badges",
        tools = list(
          as_badge("New|badge-info"),
          as_badge("3|badge-warning")
        ),
        'Add badges to the top-right corder. ',
        'Use "|" to indicate the badge classes; ',
        'for example: "badge-info", "badge-warning"...'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Default Tools",
        resizable = TRUE,
        tools = list(
          card_tool(widget = "link", href = "https://github.com/dipterix"),
          card_tool(widget = "refresh"),
          card_tool(widget = "collapse"),
          card_tool(widget = "maximize")
        ),
        # class_body =
        plotOutput(ns("card_defaulttool_plot"), height = "100%")
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Custom Tools",
        class_body = "min-height-400",
        tools = list(
          card_tool(inputId = ns("card_tool_modal"), widget = "custom",
                    title = "Show alert", icon = "bell")
        ),
        'Click the bell icon (', as_icon("bell"),
        ') at the top-right corner to show a pop-up alert', br(),
        "The reaction requires server-side shiny observer. ",
        "Go to 'server.R', add:",
        pre(
          'observeEvent(input$card_tool_modal, {',
          '  shiny::showModal(shiny::modalDialog(',
          '    "Click to dismiss",',
          '    title = "Alert", easyClose = TRUE',
          '  ))',
          '})'
        )
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Collapsed",
        start_collapsed = TRUE,
        class_body = "min-height-400 no-padding",
        tools = list(
          as_badge("30 messages |badge-primary"),
          card_tool(inputId = ns("card_tool_rerun"), widget = "custom",
                    title = "Re-run", icon = "random"),
          card_tool(widget = "collapse", start_collapsed = TRUE)
        ),
        p(
          style = "padding: 10px; margin: 0;",
          "Click the shuffle (", as_icon("random"), ") button."
        ),
        plotOutput(ns("card_tool_plot"), height = "354px")
      )
    )),
  )
}
