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
    column(width = 6L,
           infobox_with_code(info_box(
             span(class = "info-box-text", "With Progress | ",
                  actionLink(
                    ns("infobox_make_progress"), "Keep clicking me"
                  )),
             progressOutput(ns("infobox_progress")),
             icon = "sync"
           )))
  )

}


