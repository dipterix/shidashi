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

