library(shiny)
library(shidashi)
ui_notification <- function(){
  column(
    width = 6L,
    actionButton(ns("notif_1"), "Default notification", width = "auto"),
    actionButton(ns("notif_2"), "autohide = FALSE", width = "auto"),
    actionButton(ns("notif_3"), "With title, subtitle, and icon", width = "auto"),
    actionButton(ns("notif_4"), "With different types", width = "auto"),
    actionButton(ns("notif_5"), "Notification that does not close", width = "auto"),
    actionButton(ns("notif_6"), "With shiny components", width = "auto"),
    actionButton(ns("notif_7"), "With progress bar", width = "auto"),
    actionButton(ns("notif_8"), "Clear progress bar", width = "auto")
  )
}


server_notification <- function(input, output, session, ...){
  observeEvent(input$notif_1, {
    show_notification("This is a default notification. It automatically hides itself after 5 seconds, or you can close it via `x` button.")
  })
  observeEvent(input$notif_2, {
    show_notification(
      message = "This notification does not automatically hide itself",
      autohide = FALSE
    )
  })
  observeEvent(input$notif_3, {
    show_notification(
      message = "This notification has title and subtitle",
      autohide = FALSE,
      title = "Hi there!",
      subtitle = "Welcome!",
      icon = "kiwi-bird"
    )
  })
  observeEvent(input$notif_4, {
    show_notification(
      message = "This validation process has finished. You are welcome to proceed.",
      autohide = FALSE,
      title = "Success!",
      subtitle = "type='success'",
      type = "success"
    )
    show_notification(
      message = "Here are some information.",
      autohide = FALSE,
      title = "Information",
      subtitle = "type='info'",
      type = "info"
    )
    show_notification(
      message = "Here are some information.",
      autohide = FALSE,
      title = "Attention!",
      subtitle = "type='warning'",
      type = "warning"
    )
    show_notification(
      message = "Here are some information.",
      autohide = FALSE,
      title = "Error!",
      subtitle = "type='danger'",
      type = "danger"
    )

  })
  observeEvent(input$notif_5, {
    show_notification(
      message = "This notification cannot be closed. It does not automatically disappear. You have to call `clear_notifications` in R to remove it. This is helpful when you are running a process but do not want the users think the process is cancelable.",
      close = FALSE,
      autohide = FALSE,
      title = "Running...",
      type = "info"
    )
  })
  output$notif_6_out <- renderPlot({
    plot(1:10, col = input$notif_6_inp)
  })
  observeEvent(input$notif_6, {
    show_notification(
      message = div(
        selectInput(ns("notif_6_inp"), "Choose a color?",
                    choices = c("red", "blue", "green", "yellow")),
        plotOutput(ns("notif_6_out"), height = "300px")
      ),
      autohide = FALSE,
      title = "Shiny inputs & outputs",
    )
  })
  observeEvent(input$notif_7, {
    show_notification(
      message = div(
        "The wavelet might take a while to run. Grub a cup of coffee and wait.",
        progressOutput(ns("notif_7_prg"))
      ),
      autohide = FALSE,
      title = "Brewing",
      icon = "coffee",
      close = FALSE,
      class = "notif_7_autoclose"
    )
    on.exit({
      clear_notifications(class = "notif_7_autoclose")
    })

    progress <- shiny_progress(title = "Running", max = 10, outputId = "notif_7_prg")
    for(i in 1:10){
      Sys.sleep(0.5)
      progress$inc(detail = paste("Channel", i))
    }

  })

  observeEvent(input$notif_8, {
    clear_notifications()
  })
}

