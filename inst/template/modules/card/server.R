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
    if(input$add_card %% 2) {
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
    } else {
      card_tabset_remove(
        inputId = "card_tabset_expand_demo",
        title = "More..."
      )
    }

  })

  observeEvent(input$switch_tab_a, {
    card_tabset_activate(
      inputId = "card_control_1",
      title = "Tab A"
    )
  })
  observeEvent(input$add_tab_a, {
    card_tabset_insert(
      inputId = "card_control_1",
      title = sample(LETTERS, 1),
      tags$code("card_tabset_insert(...)")
    )
  })

  observeEvent(input$card_control_2_open, {
    card2_open("card_control_2")
  })
  observeEvent(input$card_control_2_close, {
    card2_close("card_control_2")
  })
  observeEvent(input$card_control_2_toggle, {
    card2_toggle("card_control_2")
  })

  observeEvent(input$card_control_3_collapse, {
    card_operate("card_control_3", "collapse")
  })
  observeEvent(input$card_control_3_expand, {
    card_operate("card_control_3", "expand")
  })
  observeEvent(input$card_control_3_maximize, {
    card_operate("card_control_3", "maximize")
  })
  observeEvent(input$card_control_3_minimize, {
    card_operate("card_control_3", "minimize")
  })

}
