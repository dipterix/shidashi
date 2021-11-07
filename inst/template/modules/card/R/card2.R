
ui_card2 <- function(){

  card_ui <- card2(
    title = "Card2 Example",
    class_body = "height-300",
    tools = list(
      card_tool(widget = "link", href = "https://github.com/dipterix"),
      card_tool(widget = "refresh"),
      card_tool(widget = "collapse"),
      card_tool(widget = "maximize")
    ),
    body_main = plotOutput(
      outputId = ns("card2_plot"),
      height = "100%"
    ),
    body_side = fluidRow(
      column( 6L,
              textInput(ns("card2_plot_title"), "Plot title")
      ),
      column( 6L,
              sliderInput(ns("card2_plot_npts"), "# of points",
                          min = 1, max = 100, value = 10, step = 1, round = TRUE)
      )
    )
  )

  shiny::tagList(
    shiny::column( width = 4L, card_ui ),
    shiny::column(
      width = 8L,
      card_tabset(
        class_body = "height-300 overflow-y-auto",
        inputId = ns("card2_code_cardset"),
        "UI code" = fluidRow(
          column(
            width = 12L,
            html_highlight_code(
              get_construct_string(card_ui), quoted = TRUE,
              width.cutoff = 80L, indent = 2, wrap=TRUE,
              args.newline = TRUE, blank = FALSE, copy_on_click = TRUE,
              hover = "overflow-auto"
            )
          )
        ),
        "server.R" = fluidRow(
          column(
            width = 12L,
            html_highlight_code(
              output$card2_plot <- renderPlot({
                npoints <- input$card2_plot_npts
                title <- input$card2_plot_title
                if(!length(title) || title == ''){
                  title <- "Normal Q-Q Plot"
                }
                qqnorm(rnorm(npoints), main = title)
                abline(a = 0, b = 1, col = 'orange3', lty = 2)
              }),
              hover = "overflow-auto"
            )
          )
        )
      )
      #              div(
      # style = "max-height: 450px",
      # html_highlight_code(get_construct_string(card_ui), quoted = TRUE)
    )
  )
}
