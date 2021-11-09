library(shiny)
library(shinytemplates)

#' During the run-time, the script in the following folders
#' will be loaded:
#' * R/
#' * modules/<ID>/R
#' You can run the following script to debug
if(FALSE){
  source('inst/template/R/interface.R')
  source('inst/template/modules/test/R/aaa.R')
  session <- shiny::MockShinySession$new()
}

#' Defines the module server
server <- function(input, output, session, ...){

  shared_data <- shinytemplates::register_session_id(session)

  output$infobox_progress <- renderProgress({
    val <- input$infobox_make_progress %% 5
    if(val == 2){
      stop("Click again")
    }
    list(
      value = val / 4 * 100,
      description = sprintf("Progress %d of 4", val)
    )
  })

  observeEvent(input$card_tool_modal, {
    shiny::showModal(shiny::modalDialog(
      "Click to dismiss",
      title = "Alert", easyClose = TRUE
    ))
  })

  output$card_defaulttool_plot <- renderPlot({
    plot(rnorm(20))
  })

  output$card_tool_plot <- renderPlot({
    input$card_tool_rerun
    hist(rnorm(1000))
  })

  output$card2_plot <- renderPlot({
    npoints <- input$card2_plot_npts
    title <- input$card2_plot_title
    if(!length(title) || title == ''){
      title <- "Normal Q-Q Plot"
    }
    qqnorm(rnorm(npoints), main = title)
    abline(a = 0, b = 1, col = 'orange3', lty = 2)
  })

  observeEvent(input$add_card, {
    card_tabset_insert(
      inputId = "card_tabset_expand_demo",
      title = "More...", active = TRUE,
      h4("A hidden playground!"),
      hr(),
      p("You can use `card_tabset_insert` to ",
        "insert cards to the cardset. ",
        "However, if you try to insert a card ",
        "whose title has already existed, ",
        "a notification will pop up to warn you."),
      p("Now, try to click on the kiwi-bird (",
        as_icon("kiwi-bird"), ") again.")
    )
  })

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
