create_barebone <- function(path) {
  dir.create(path, showWarnings = FALSE, recursive = TRUE)
  src <- system.file("builtin-templates", "AdminLTE3-bare", package = "shidashi")
  fs <- list.files(src, full.names = TRUE, recursive = FALSE, all.files = FALSE,
                   no.. = TRUE, include.dirs = TRUE)
  # Exclude node_modules, src, and lock files from copy
  fs <- fs[!basename(fs) %in% c("node_modules", "src", "package-lock.json")]
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
        "library(shiny)",
        "",
        "server <- function(input, output, session) {",
        "",
        "  shidashi::enable_input_broadcast(session)",
        "  shidashi::enable_input_sync(session)",
        "",
        "  # Load and dispatch module server on navigation",
        "  shiny::observeEvent(session$clientData$url_search, {",
        "    req <- list(QUERY_STRING = session$clientData$url_search)",
        "    resource <- shidashi::load_module(request = req)",
        "    if (resource$has_module) {",
        "      module_table <- shidashi::module_info()",
        "      module_table <- module_table[module_table$id %in%",
        "        resource$module$id, ]",
        "      if (nrow(module_table)) {",
        "        group_name <- as.character(module_table$group[[1]])",
        "        if (is.na(group_name)) {",
        "          group_name <- \"<no group>\"",
        "        }",
        "        if (system.file(package = \"logger\") != \"\") {",
        "          logger::log_info(\"Loading - { module_table$label[1] } ({group_name}/{ module_table$id })\")",
        "        }",
        "        shiny::moduleServer(resource$module$id, resource$module$server,",
        "          session = session)",
        "      }",
        "    }",
        "  })",
        "}"
      ), file.path(path, "server.R"))
  }

  dir.create(file.path(path, "R"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(path, "modules", "module_id", "R"), showWarnings = FALSE, recursive = TRUE)

  # /R/common.R
  {
    writeLines(
      c(
        "library(shiny)",
        "page_title <- function(complete = TRUE) {",
        "  if (complete) {",
        "    \"Shiny Dashboard Template - Barebone\"",
        "  } else {",
        "    \"ShiDashi\"",
        "  }",
        "}",
        "page_logo <- function(size = c(\"normal\", \"small\", \"large\")) {",
        "  # Relative path to your logo icon in www/",
        "  \"shidashi/img/icon.png\"",
        "}",
        "page_loader <- function() {",
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
        "body_class <- function() {",
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
        "nav_class <- function() {",
        "  c(",
        "    \"main-header\",",
        "    \"navbar\",",
        "    \"navbar-expand\",",
        "    \"navbar-dark\",",
        "    \"navbar-primary\"",
        "  )",
        "}",
        "",
        "module_breadcrumb <- function() {}"
      ),
      con = file.path(path, "R", "common.R"))
  }

  # /modules/module_id/R/module-ui.R
  {
    writeLines(
      c(
        "library(shiny)",
        "library(shidashi)",
        "",
        "ui <- function() {",
        "  fluidPage(",
        "    fluidRow(",
        "      column(",
        "        width = 12L,",
        "        # remember to add ns, which is given as shiny::NS(\"module_id\")",
        "        plotOutput(ns(\"plot\"))",
        "      )",
        "    )",
        "  )",
        "}",
        "",
        "server_module_id <- function(input, output, session, ...) {",
        "  shidashi::register_session(session)",
        "",
        "  output$plot <- renderPlot({",
        "    theme <- shidashi::get_theme()",
        "    set.seed(1)",
        "    par(",
        "      bg = theme$background, fg = theme$foreground,",
        "      col.main = theme$foreground,",
        "      col.axis = theme$foreground,",
        "      col.lab = theme$foreground",
        "    )",
        "    hist(rnorm(1000))",
        "  })",
        "}"
      ),
      con = file.path(path, "modules", "module_id", "R", "module-ui.R")
    )
  }

  # /modules/module_id/server.R
  {
    writeLines(
      c(
        "library(shiny)",
        "library(shidashi)",
        "",
        "server <- function(input, output, session, ...) {",
        "  server_module_id(input, output, session, ...)",
        "}"
      ),
      con = file.path(path, "modules", "module_id", "server.R")
    )
  }

  # /agents/ - MCP tools and skills
  create_barebone_agents(path)

  # /modules/module_id/agents.yaml
  {
    writeLines(
      c(
        "enabled: yes",
        "tools:",
        "- name: hello_world",
        "  category:",
        "  - exploratory",
        "  enabled: yes",
        "- name: get_shiny_input_values",
        "  category:",
        "  - exploratory",
        "  enabled: yes",
        "skills:",
        "- name: greet",
        "  category:",
        "  - executing",
        "  enabled: yes",
        "parameters:",
        "  system_prompt: You are an R shiny expert. You have access to the shiny",
        "    application via provided tools."
      ),
      con = file.path(path, "modules", "module_id", "agents.yaml")
    )
  }

  invisible()
}


create_barebone_bslib <- function(path) {
  dir.create(path, showWarnings = FALSE, recursive = TRUE)
  src <- system.file("builtin-templates", "bslib-bare", package = "shidashi")
  if (!nchar(src) || !dir.exists(src)) {
    stop("Cannot find bslib-bare template. Please update the `shidashi` package.")
  }
  fs <- list.files(src, full.names = TRUE, recursive = FALSE, all.files = FALSE,
                   no.. = TRUE, include.dirs = TRUE)
  # Exclude node_modules, src, and lock files from copy
  fs <- fs[!basename(fs) %in% c("node_modules", "src", "package-lock.json")]
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
        "library(shiny)",
        "",
        "server <- function(input, output, session) {",
        "",
        "  shidashi::enable_input_broadcast(session)",
        "  shidashi::enable_input_sync(session)",
        "",
        "  # Load and dispatch module server on navigation",
        "  shiny::observeEvent(session$clientData$url_search, {",
        "    req <- list(QUERY_STRING = session$clientData$url_search)",
        "    resource <- shidashi::load_module(request = req)",
        "    if (resource$has_module) {",
        "      module_table <- shidashi::module_info()",
        "      module_table <- module_table[module_table$id %in%",
        "        resource$module$id, ]",
        "      if (nrow(module_table)) {",
        "        group_name <- as.character(module_table$group[[1]])",
        "        if (is.na(group_name)) {",
        "          group_name <- \"<no group>\"",
        "        }",
        "        if (system.file(package = \"logger\") != \"\") {",
        "          logger::log_info(\"Loading - { module_table$label[1] } ({group_name}/{ module_table$id })\")",
        "        }",
        "        shiny::moduleServer(resource$module$id, resource$module$server,",
        "          session = session)",
        "      }",
        "    }",
        "  })",
        "",
        "  output$drawer_output <- shiny::renderPrint({",
        "    module_data <- shidashi::active_module()",
        "    if (is.null(module_data)) {",
        "      \"No module\"",
        "    } else {",
        "      utils::str(module_data)",
        "    }",
        "  })",
        "",
        "  # Chatbot server runs per-module (injected by modules.R when",
        "  # agents.yaml has enabled: yes).  No chatbot_server() call here.",
        "}"
      ), file.path(path, "server.R"))
  }

  dir.create(file.path(path, "R"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(path, "modules", "module_id", "R"), showWarnings = FALSE, recursive = TRUE)

  # /R/common.R
  {
    writeLines(
      c(
        "library(shiny)",
        "page_title <- function(complete = TRUE) {",
        "  if (complete) {",
        "    \"Shiny Dashboard Template - bslib\"",
        "  } else {",
        "    \"ShiDashi\"",
        "  }",
        "}",
        "",
        "page_logo <- function(size = c(\"normal\", \"small\", \"large\")) {",
        "  \"shidashi/img/icon.png\"",
        "}",
        "page_loader <- function() {",
        "  NULL",
        "}",
        "",
        "body_class <- function() {",
        "  c(",
        "    #--- Start as dark-mode ---",
        "    \"dark-mode\",",
        "",
        "    # drawer has no overlay",
        "    \"shidashi-drawer-no-overlay\"",
        "  )",
        "}",
        "",
        "nav_class <- function() {",
        "  c(",
        "    \"shidashi-header\",",
        "    \"navbar\",",
        "    \"navbar-expand\"",
        "  )",
        "}",
        "",
        "sidebar_class <- function() {",
        "  c(",
        "    #--- Start as dark-mode ---",
        "    \"dark-mode\"",
        "  )",
        "}",
        "",
        "module_breadcrumb <- function() {}",
        ""
      ),
      con = file.path(path, "R", "common.R"))
  }

  # /modules/module_id/R/module-ui.R
  {
    writeLines(
      c(
        "library(shiny)",
        "library(shidashi)",
        "",
        "ui <- function() {",
        "  fluidPage(",
        "    fluidRow(",
        "      column(",
        "        width = 12L,",
        "        # remember to add ns, which is given as shiny::NS(\"module_id\")",
        "        plotOutput(ns(\"plot\"))",
        "      )",
        "    )",
        "  )",
        "}",
        "",
        "server_module_id <- function(input, output, session, ...) {",
        "  shidashi::register_session(session)",
        "",
        "  output$plot <- renderPlot({",
        "    theme <- shidashi::get_theme()",
        "    set.seed(1)",
        "    par(",
        "      bg = theme$background, fg = theme$foreground,",
        "      col.main = theme$foreground,",
        "      col.axis = theme$foreground,",
        "      col.lab = theme$foreground",
        "    )",
        "    hist(rnorm(1000))",
        "  })",
        "}"
      ),
      con = file.path(path, "modules", "module_id", "R", "module-ui.R")
    )
  }

  # /modules/module_id/server.R
  {
    writeLines(
      c(
        "library(shiny)",
        "library(shidashi)",
        "",
        "server <- function(input, output, session, ...) {",
        "  server_module_id(input, output, session, ...)",
        "}"
      ),
      con = file.path(path, "modules", "module_id", "server.R")
    )
  }

  # /agents/ - MCP tools and skills
  create_barebone_agents(path)

  # /modules/module_id/agents.yaml
  {
    writeLines(
      c(
        "enabled: yes",
        "tools:",
        "- name: hello_world",
        "  category:",
        "  - exploratory",
        "  enabled: yes",
        "- name: get_shiny_input_values",
        "  category:",
        "  - exploratory",
        "  enabled: yes",
        "skills:",
        "- name: greet",
        "  category:",
        "  - executing",
        "  enabled: yes",
        "parameters:",
        "  system_prompt: You are an R shiny expert. You have access to the shiny",
        "    application via provided tools."
      ),
      con = file.path(path, "modules", "module_id", "agents.yaml")
    )
  }

  invisible()

}


# Internal helper: create agents/ directory with MCP tools and skills
create_barebone_agents <- function(path) {
  # Create directory structure
  dir.create(file.path(path, "agents", "tools"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(path, "agents", "skills", "greet", "scripts"), showWarnings = FALSE, recursive = TRUE)

  # agents/tools/hello_world.R
  writeLines(
    c(
      "# agents/tools/hello_world.R",
      "#",
      "# Root-level MCP tool: Returns a greeting.",
      "# Used to verify the MCP tunnel works end-to-end.",
      "",
      "hello_world <- shidashi::mcp_wrapper(",
      "  function(session) {",
      "    ellmer::tool(",
      "      fun = function(name = \"World\") {",
      "        paste0(\"Hello, \", name, \"!\")",
      "      },",
      "      name = \"hello_world\",",
      "      description = \"Returns a greeting. Used to verify the MCP tunnel works.\",",
      "      arguments = list(",
      "        name = ellmer::type_string(",
      "          \"Name to greet (default: 'World')\",",
      "          required = FALSE",
      "        )",
      "      )",
      "    )",
      "  }",
      ")"
    ),
    con = file.path(path, "agents", "tools", "hello_world.R")
  )

  # agents/tools/get_shiny_input_values.R
  writeLines(
    c(
      "# agents/tools/get_shiny_input_values.R",
      "#",
      "# Root-level MCP tool: Read Shiny input values from the bound session.",
      "",
      "get_shiny_input_values <- shidashi::mcp_wrapper(",
      "  function(session) {",
      "",
      "    # Capture the live session in closure",
      "    bound_session <- session",
      "",
      "    ellmer::tool(",
      "      fun = function(input_ids = character()) {",
      "        input_ids <- as.character(input_ids[!is.na(input_ids)])",
      "        values <- tryCatch({",
      "          if (is.null(input_ids) || length(input_ids) == 0L) {",
      "            shiny::isolate(shiny::reactiveValuesToList(bound_session$input))",
      "          } else {",
      "            structure(",
      "              names = input_ids,",
      "              lapply(input_ids, function(id) {",
      "                shiny::isolate(bound_session$input[[id]])",
      "              })",
      "            )",
      "          }",
      "        }, error = function(e) {",
      "          stop(\"Error reading inputs: \", conditionMessage(e))",
      "        })",
      "      },",
      "      name = \"get_shiny_input_values\",",
      "      description = \"Read R-Shiny input values from the bound session.\",",
      "      arguments = list(",
      "        input_ids = ellmer::type_array(",
      "          items = ellmer::type_string(),",
      "          description = \"Input IDs to read. If empty or omitted, returns all input values.\",",
      "          required = FALSE",
      "        )",
      "      )",
      "    )",
      "  }",
      ")"
    ),
    con = file.path(path, "agents", "tools", "get_shiny_input_values.R")
  )

  # agents/skills/greet/SKILL.md
  writeLines(
    c(
      "---",
      "name: greet",
      "description: Greets a user by name using a simple R script",
      "---",
      "",
      "## Instructions",
      "",
      "This skill demonstrates the skill system. It runs a short R script",
      "that prints a personalised greeting.",
      "",
      "### Usage",
      "",
      "1. Call `action='script'`, `file_name='greet.R'`, `args=['World']`",
      "2. The script prints: `Hello, World!`",
      "",
      "### Arguments",
      "",
      "- `args[1]`: The name to greet (default: `\"World\"`)"
    ),
    con = file.path(path, "agents", "skills", "greet", "SKILL.md")
  )

  # agents/skills/greet/scripts/greet.R
  writeLines(
    c(
      "#!/usr/bin/env Rscript",
      "# greet.R - Simple greeting script for the demo skill",
      "#",
      "# Usage: Rscript greet.R [name]",
      "# Output: Hello, <name>!",
      "",
      "args <- commandArgs(trailingOnly = TRUE)",
      "name <- if (length(args) >= 1L) args[[1L]] else \"World\"",
      "",
      "cat(sprintf(\"Hello, %s!\\n\", name))"
    ),
    con = file.path(path, "agents", "skills", "greet", "scripts", "greet.R")
  )

  # agents/tool-schema.yaml
  # Pre-listed tool schemas for MCP clients that do not support
  # dynamic deferred tools.
  writeLines(
    c(
      "# agents/tool-schema.yaml",
      "#",
      "# Pre-listed tool schemas for MCP clients that do not support",
      "# dynamic deferred tools. These schemas are advertised in `tools/list`",
      "# even before a Shiny session is bound. Calling the tools still",
      "# requires a bound session.",
      "#",
      "# Skills (agents/skills/) are auto-discovered and do NOT need to be",
      "# listed here.",
      "",
      "tools:",
      "- name: hello_world",
      "  description: \"Returns a greeting. Used to verify the MCP tunnel works.\"",
      "  inputSchema:",
      "    type: object",
      "    properties:",
      "      name:",
      "        type: string",
      "        description: \"Name to greet (default: 'World')\""
    ),
    con = file.path(path, "agents", "tool-schema.yaml")
  )

  invisible()
}
