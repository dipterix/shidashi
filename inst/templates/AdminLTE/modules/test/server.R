library(shiny)
library(shinytemplates)

#' During the run-time, the script in the following folders
#' will be loaded:
#' * R/
#' * modules/<ID>/R
#' You can run the following script to debug
if(FALSE){
  source('inst/templates/AdminLTE/R/interface.R')
  source('inst/templates/AdminLTE/modules/test/R/aaa.R')
  session <- shiny::MockShinySession$new()
}

#' Defines the module server
server <- function(input, output, session, ...){

  list2env(list(session = session), envir=globalenv())
  shinytemplates::register_session_id(session, shared_id = "testtt")

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

  shiny::observeEvent(input$in3, {
    print('hhhh')
  })

  shiny::observeEvent(input$add_card, {
    print("Adding card")
    insert_card_tab("output_tabset", title = "A new tab", session = session,
                    shiny::textInput(ns("in3"), "New input"))

    p <- dipsaus::progress2("title")
    Sys.sleep(2)

    p$inc("details")
    clear_notifications()


  })


  root_session <- session$rootScope()
  list2env(list(root_session = root_session), envir=globalenv())
  observeEvent(root_session$input[["@shinytemplates@"]], {
    try({

      message <- RcppSimdJson::fparse(root_session$input[["@shinytemplates@"]])
      print(message)

    }, silent = FALSE)
  })


}
