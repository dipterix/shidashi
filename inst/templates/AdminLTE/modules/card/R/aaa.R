library(shiny)
library(shinytemplates)
if(FALSE){
  template_settings$set(
    'root_path' = "inst/templates/AdminLTE/"
  )

  .module_id <- "ui_example"
  ns <- shiny::NS(.module_id)
}

module_title <- function(){
  modules <- module_info()
  modules$label[modules$id == .module_id]
}


card_with_code <- function(expr, env = parent.frame(),
                           class = "height-50", width.cutoff = 25L){
  expr <- substitute(expr)
  x <- eval(expr, envir = env)

  # code <- show_ui_code(x, class = class, width.cutoff = width.cutoff)
  # expr[["class_foot"]] <- "display-block bg-gray-90 no-padding code-display fill-width"
  code <- clipboardOutput(
    clip_text = format_text_r(
      get_construct_string(x), quoted = TRUE,
      width.cutoff = width.cutoff
    ), class = "float-right", as_card_tool = TRUE
  )
  expr[["footer"]] <- code
  eval(expr, envir = env)
}


