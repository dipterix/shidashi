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

  list2env(list(session = session), envir=globalenv())
  shared_data <- shinytemplates::register_session_id(session)

  shiny::observeEvent(input$configure_card, {
    shiny::showModal(
      shiny::modalDialog(
        title = "Configure",
        easyClose = TRUE,
        "Under construction. Click anywhere outside of this pop-up to dismiss."
      )
    )
  })

  output$plot <- shiny::renderPlot({
    plot(1:10, main = input$in1)
  })

  shiny::observeEvent(input$add_card, {
    card_tabset_insert("output_tabset", title = "A new tab", session = session,
                    shiny::textInput(ns("in3"), "New input"))

    p <- dipsaus::progress2("title")
    Sys.sleep(2)

    p$inc("details")
    clear_notifications()


  })

  observeEvent({
    shared_data$reactives[[ns("in2")]]
  }, {
    val <- shared_data$reactives[[ns("in2")]]
    shiny::updateTextInput(session, "in2", value = val)
  })


}
