ui_info_box_basic <- function(){
  tagList(
    column(width = 3L,
           infobox_with_code(
             info_box("Message", icon = NULL)
           )),
    column(width = 3L,
           infobox_with_code(
             info_box(icon = NULL,
                      span(class = "info-box-text", "Likes"),
                      span(class = "info-box-number", "20,331"))
           ))
  )
}

ui_info_box_advanced <- function(){

  tagList(
    column(width = 3L,
           infobox_with_code(
             info_box(icon = "cogs",
                      span(class = "info-box-text", 'Configurations'),
                      span(class = "info-box-number", "With icon")))
           ),
    column(width = 3L,
           infobox_with_code(
             info_box(icon = "thumbs-up",
                      class_icon = "bg-green",
                      span(class = "info-box-text", 'Likes'),
                      span(class = "info-box-number", "Colored icon")))
           ),
    column(width = 3L,
           infobox_with_code(
             info_box(span(class = "info-box-text", 'Calendars'),
                      span(class = "info-box-number", "4 items"),
                      icon = "calendar-alt",
                      class = "bg-yellow", class_icon = NULL)
           )
    ),
    column(width = 3L,
           infobox_with_code(
             info_box(span(class = "info-box-text", 'Yes!'),
                      span(class = "info-box-number", 'Colored differently'), icon = "star",
                      class = "bg-yellow")
             )
    ),
    column( width = 8L,
            infobox_with_code(
              title = "Info-box (progress bar)",
              info_box(
                span(class="info-box-text", "Progress | ",
                     actionLink(ns("infobox_make_progress"), "Keep clicking me"),
                     " | ",
                     actionLink(ns("infobox_make_progress_alt"), "Alternative process")),
                progressOutput(ns("infobox_progress")),
                icon = "sync"
              )
            )
    ),
  )

}

server_info_box <- function(input, output, session, ...){

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

  observeEvent(input$infobox_make_progress_alt, {
    progress <- shiny_progress(title = "Alternative Procedure", max = 10, outputId = "infobox_progress")
    for(i in 1:10){
      progress$inc(sprintf("Step %s", i))
      Sys.sleep(1)
    }

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


}
