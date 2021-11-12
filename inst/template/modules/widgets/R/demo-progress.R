ui_progress <- function(){
  tagList(
    column(
      width = 12L,
      card(
        title = "Different styles of progress",
        fluidRow(
          column(
            width = 6L,
            progressOutput(
              ns("prog_1"), description = 'class = "bg-primary" (default)',
              value = 40),
            progressOutput(
              ns("prog_2"), description = 'class = "bg-info"',
              class = "bg-info", value = 100),
            progressOutput(
              ns("prog_3"), description = 'class = "bg-success"',
              class = "bg-success", value = 80),
            progressOutput(
              ns("prog_4"), description = 'class = "bg-warning"',
              class = "bg-warning", value = 70),
            progressOutput(
              ns("prog_5"), description = 'class = "bg-danger"',
              class = "bg-danger", value = 50)
          ),
          column(
            width = 6L,
            p(
              span(
                class = "inline-all",
                "There are two ways of changing the progress. ",
                "The first approach is via ",
                tags$code("renderProgress({...})"),
                " method:",
                actionLink(ns("prog_btn1"), "click me!")
              )
            ),
            p(
              span(
                class = "inline-all",
                "The second choice is to use ",
                tags$code("shiny_progress()"),
                " function with input id:",
                actionLink(ns("prog_btn2"), "click me!")
              )
            ),
            p(
              "Here's an example of embedding progress bar in the notification.",
              actionButton(ns("prog_btn3"), "Click me!")
            )
          )
        )
      )
    )
  )
}


server_progress <- function(input, output, session, ...){

  data <- fastmap::fastmap()
  data$set("progress", 0)

  output$prog_1 <- renderProgress({
    # at the end of the expression, return the percentage
    # or a list(value=, description=)
    print(input$prog_btn1)

    progress <- data$get("progress") + 10
    if(progress > 100){
      progress <- 0
    }
    data$set("progress", progress)
    list(
      value = progress,
      description = sprintf("Progress: %.0f%%", progress)
    )

  })

  observeEvent(input$prog_btn2, {
    progress = shiny_progress(title = "Method 2", max = 10, outputId = "prog_1")
    for(i in 1:10){
      progress$inc(sprintf("step - %d", i))
      Sys.sleep(0.3)
    }
  }, ignoreInit = TRUE, ignoreNULL = TRUE)

  observeEvent(input$prog_btn3, {
    show_notification(
      message = div(
        "The wavelet might take a while to run. Grub a cup of coffee and wait.",
        progressOutput(ns("notif_7_prg"), class = "bg-success")
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
}
