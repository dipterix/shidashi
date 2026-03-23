library(shiny)

# Debug
if (FALSE) {
  template_settings$set(
    'root_path' = "inst/builtin-templates/bslib-bare/"
  )
}

server <- function(input, output, session){

  shared_data <- shidashi::register_session_id(session)
  shared_data$enable_broadcast()
  shared_data$enable_sync()

  # Load and dispatch module server on navigation (register first)
  shiny::observeEvent(session$clientData$url_search, {
    req <- list(QUERY_STRING = session$clientData$url_search)
    resource <- shidashi::load_module(request = req)
    if (resource$has_module) {

      module_table <- shidashi::module_info()
      module_table <- module_table[module_table$id %in% resource$module$id, ]
      if (nrow(module_table)) {
        group_name <- as.character(module_table$group[[1]])
        if (is.na(group_name)) {
          group_name <- "<no group>"
        }
        if (system.file(package = "logger") != '') {
          logger::log_info("Loading - { module_table$label[1] } ({group_name}/{ module_table$id })")
        }
        shiny::moduleServer(resource$module$id, resource$module$server, session = session)
      }
    }
  })

  output$drawer_output <- shiny::renderPrint({
    module_data <- shidashi::active_module()
    if (is.null(module_data)) {
      "No module"
    } else {
      utils::str(module_data)
    }
  })
}
