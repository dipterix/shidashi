
create_barebone <- function(path){
  dir.create(path, showWarnings = FALSE, recursive = TRUE)
  src <- system.file("builtin-templates", "AdminLTE3-bare", package = "shidashi")
  fs <- list.files(src, full.names = TRUE, recursive = FALSE, all.files = FALSE,
                   no.. = TRUE, include.dirs = TRUE)
  file.copy(
    from = fs,
    to = path,
    overwrite = TRUE,
    recursive = TRUE,
    copy.date = TRUE
  )

  # /server.R
  {
    writeLines(
      c(
        "{",
        "    library(shiny)",
        "    server <- function(input, output, session) {",
        "        shiny::observeEvent(session$clientData$url_search, {",
        "            req <- list(QUERY_STRING = session$clientData$url_search)",
        "            resource <- shidashi::load_module(request = req)",
        "            if (resource$has_module) {",
        "                module_table <- shidashi::module_info()",
        "                module_table <- module_table[module_table$id %in% ",
        "                  resource$module$id, ]",
        "                if (nrow(module_table)) {",
        "                  group_name <- as.character(module_table$group[[1]])",
        "                  if (is.na(group_name)) {",
        "                    group_name <- \"<no group>\"",
        "                  }",
        "                  if (system.file(package = \"logger\") != \"\") {",
        "                    logger::log_info(\"Loading - { module_table$label[1] } ({group_name}/{ module_table$id })\")",
        "                  }",
        "                  shiny::moduleServer(resource$module$id, resource$module$server, ",
        "                    session = session)",
        "                }",
        "            }",
        "        })",
        "    }",
        "}"
      ), file.path(path, "server.R"))

  }

  dir.create(file.path(path, 'R'), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(path, 'modules', 'module_id', 'R'), showWarnings = FALSE, recursive = TRUE)

  # /R/common.R
  {
    writeLines(
      c(
        "library(shiny)",
        "page_title <- function(complete = TRUE){",
        "  if(complete){",
        "    \"Shiny Dashboard Template - Barebone\"",
        "  } else {",
        "    \"ShiDashi\"",
        "  }",
        "}",
        "page_logo <- function(size = c(\"normal\", \"small\", \"large\")){",
        "  # Relative path to your logo icon in www/",
        "  # \"logo.png\"",
        "  NULL",
        "}",
        "page_loader <- function(){",
        "  # if no loader is needed, then return NULL",
        "  shiny::div(",
        "    class = \"preloader flex-column justify-content-center align-items-center\",",
        "    shiny::img(",
        "      class = \"animation__shake\",",
        "      src = page_logo(\"large\"),",
        "      alt = \"Logo\", height=\"60\", width=\"60\"",
        "    )",
        "  )",
        "}",
        "body_class <- function(){",
        "  c(",
        "    #--- Fix the navigation banner ---",
        "    #\"layout-navbar-fixed\",",
        "",
        "    #--- Collapse the sidebar at the beginning ---",
        "    # \"sidebar-collapse\",",
        "",
        "    #--- Let control sidebar open at the beginning ---",
        "    # \"control-sidebar-slide-open\",",
        "",
        "    #--- Fix the sidebar position ---",
        "    \"layout-fixed\",",
        "",
        "    #--- Default behavior when collapsing sidebar",
        "    # \"sidebar-mini\", \"sidebar-mini-md\", \"sidebar-mini-xs\"",
        "",
        "    #--- Hide the navbar-nav-iframe",
        "    \"navbar-iframe-hidden\",",
        "",
        "    #--- Start as dark-mode ---",
        "    \"dark-mode\"",
        "",
        "    #--- Make scrollbar thinner ---",
        "    # \"fancy-scroll-y\"",
        "",
        "  )",
        "}",
        "nav_class <- function(){",
        "  c(",
        "    \"main-header\",",
        "    \"navbar\",",
        "    \"navbar-expand\",",
        "    \"navbar-dark\",",
        "    \"navbar-primary\"",
        "  )",
        "}",
        "",
        "module_breadcrumb <- function(){}"
      ),
      con = file.path(path, 'R', 'common.R'))
  }

  # /modules/module_id/R/chunk-1.R
  {
    writeLines(
      c(
        "library(shiny)",
        "library(shidashi)",
        "ui <- function(){",
        "",
        "  fluidPage(",
        "    fluidRow(",
        "      column(",
        "        width = 12L,",
        "",
        "        # remember to add ns, which is given as shiny::NS(\"module_id\")",
        "        plotOutput(ns(\"plot\"))",
        "      )",
        "    )",
        "  )",
        "",
        "}",
        "",
        "server_chunk_1 <- function(input, output, session, ...){",
        "",
        "  event_data <- register_session_events()",
        "",
        "  output$plot <- renderPlot({",
        "    theme <- get_theme(event_data)",
        "    set.seed(1)",
        "    par(",
        "      bg = theme$background, fg = theme$foreground,",
        "      col.main = theme$foreground,",
        "      col.axis = theme$foreground,",
        "      col.lab = theme$foreground",
        "    )",
        "    hist(rnorm(1000))",
        "  })",
        "",
        "}"
      ),
      con = file.path(path, 'modules', 'module_id', 'R', "chunk-1.R")
    )
  }

  # /modules/module_id/server.R
  {
    writeLines(
      c(
        "library(shiny)",
        "library(shidashi)",
        "",
        "server <- function(input, output, session, ...){",
        "",
        "  shared_data <- shidashi::register_session_id(session)",
        "",
        "  server_chunk_1(input, output, session, ...)",
        "",
        "}"
      ),
      con = file.path(path, 'modules', 'module_id', 'server.R')
    )
  }

  invisible()

}
