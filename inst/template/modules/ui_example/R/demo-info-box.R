infobox_with_code <- function(x, title = "",
                              class = "height-100",
                              width.cutoff = 15L){
  # Display code with width-cutoff=15
  show_ui_code(x, class = class, width.cutoff = width.cutoff,
               as_card = TRUE, card_title = title)
}

ui_info_box <- function(){

  shiny::tagList(
    # Displays Code
    column( width = 3L,
            infobox_with_code( title = "Basic info-box",
                               info_box("Message", icon = NULL))
    ),
    column( width = 3L,
            infobox_with_code( title = "Info-box with icons",
                               info_box("Icon (flag)",
                                        icon = "exclamation-circle",
                                        class_icon = "bg-danger",
                                        class = "bg-gradient-warning"))
    ),
    column( width = 3L,
            infobox_with_code( title = "Info-box (fancy text)",
                               info_box(
                                 icon = "copy",
                                 span(class="info-box-text", "Uploads"),
                                 span(class="info-box-number", "20,331")
                               ))
    ),
    column( width = 3L,
            infobox_with_code( title = "Info-box (progress bar)",
                               info_box(
                                 span(class="info-box-text", "Progress | ",
                                      actionLink(ns("infobox_make_progress"), "Keep clicking me")),
                                 progressOutput(ns("infobox_progress")),
                                 icon = "sync"
                               ))
    ),
  )

}
