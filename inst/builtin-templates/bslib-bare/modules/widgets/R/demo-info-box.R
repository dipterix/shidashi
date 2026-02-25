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
                span(class = "info-box-text", "Progress | ",
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

}
