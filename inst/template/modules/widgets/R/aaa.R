library(shiny)
library(shinytemplates)
if(FALSE){
  template_settings$set(
    'root_path' = "inst/template/"
  )

  .module_id <- "ui_example"
  ns <- shiny::NS(.module_id)
}

module_title <- function(){
  modules <- module_info()
  modules$label[modules$id == .module_id]
}


infobox_with_code <- function(x, title = "",
                              class = "height-100",
                              class_body = "padding-5 bg-gray-70"){
  # Display code with width-cutoff=15

  shiny::div(
    class = "fill-width position-relative",
    shiny::span(
      class = "position-absolute padding-bottom-5 bg-gray",
      style = "right: 0; z-index: 100;",
      clipboardOutput(clip_text = get_construct_string(x),
                      as_card_tool = TRUE, message = "Copy to clipboard")
    ),
    x
  )

}

