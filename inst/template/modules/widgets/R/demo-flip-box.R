ui_flip_box <- function(){

  shiny::tagList(
    # Displays Code
    column(
      width = 12L,
      infobox_with_code(
        flip_box(
          front = info_box(
            icon = "bookmark",
            p(
              "This is the front side. Double-click me"
            )
          ),
          back = info_box(
            icon = NULL,
            p("This is the back side. Double-click me to toggle back.")
          )
        )
      )
    ),
    column(
      width = 12L,
      infobox_with_code(
        flip_box(
          active_on = "click-front",
          inputId = ns("flip_demo_2"),
          front = info_box(
            icon = "th",
            p(
              "This is the front side. Double-click me"
            )
          ),
          back = info_box(
            icon = NULL,
            plotOutput(ns("flip_box_plot")),
            p(
              "Click this button and a progress will run. ",
              "Once the progress finishes, the box will flip back. "
            ),
            actionButton(ns("show_progress"), "Show Progress")
          )
        )
      )
    ),
    column(
      width = 12L,
      infobox_with_code(
        flip_box(
          active_on = "manual",
          inputId = ns("flip_demo_3"),
          front = info_box(
            icon = "arrow-right",
            p(
              "This is the front side. Click this button"
            ),
            actionButton(ns("flip_btn_1"), "Flip")
          ),
          back = info_box(
            icon = "arrow-left",
            p(
              "This is the back side. Click this button"
            ),
            actionButton(ns("flip_btn_2"), "Flip again")
          )
        )
      )
    )
  )

}

ui_flip_card <- function(){
  tagList(
    column(
      width = 12L,
      card(
        title = "Card with flip box",
        class_body = "no-padding",
        tools = list(
          card_tool(widget = "flip")
        ),
        flip_box(
          front = div(
            p(
              class = "padding-20",
              "While you can still flip the box by double-clicking, ",
              "alternatively, clicking the 'flip' icon in the tool bar also flips the box."
            ),
            plotOutput(ns("flip_card_plot"))
          ),
          back = div(
            class = "padding-20",
            p("The data used to generate the figure"),
            tableOutput(ns("flip_card_table"))
          )
        )
      )
    )
  )
}


server_flip_box <- function(input, output, session, ...){
  # Flip-box
  output$flip_box_plot <- renderPlot({
    plot(rnorm(100, 10*sin(seq(0, 2, length.out = 100))), pch = 16,
         ylab = "Response", las = 1)
  })

  observeEvent(input$show_progress, {
    progress <- shiny_progress(title = "Running algorithms", max = 10, shiny_auto_close = TRUE)
    for(i in 1:10){
      progress$inc(sprintf("Running part %s", i))
      Sys.sleep(0.1)
    }
    flip("flip_demo_2")
  })

  observeEvent(input$flip_btn_1, {
    flip("flip_demo_3")
  })
  observeEvent(input$flip_btn_2, {
    flip("flip_demo_3")
  })

  output$flip_card_plot <- renderPlot({
    data(iris)
    with(iris, {
      plot(Sepal.Length, Sepal.Width, col = Species, pch = 20)
    })
  })
  output$flip_card_table <- renderTable({
    data(iris)
    iris
  })

}
