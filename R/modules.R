#' @title Obtain the module information
#' @param root_path the root path of the website project
#' @param settings_file the settings file containing the module information
#' @param request 'HTTP' request string
#' @param env environment to load module variables into
#' @return A data frame with the following columns that contain the module
#' information:
#' \describe{
#' \item{\code{id}}{module id, folder name}
#' \item{\code{order}}{display order in side-bar}
#' \item{\code{group}}{group menu name if applicable, otherwise \code{NA}}
#' \item{\code{label}}{the readable label to be displayed on the side-bar}
#' \item{\code{icon}}{icon that will be displayed ahead of label, will be
#' passed to \code{\link{as_icon}}}
#' \item{\code{badge}}{badge text that will be displayed
#' following the module label, will be passed to \code{\link{as_badge}}}
#' \item{\code{url}}{the relative 'URL' address of the module.}
#' }
#' @details The module files are stored in \code{modules/} folder in your
#' project. The folder names are the module id. Within each folder,
#' there should be one \code{"server.R"}, \code{R/}, and a
#' \code{"module-ui.html"}.
#'
#' The \code{R/} folder stores R code files that generate variables,
#' which will be available to the other two files. These variables, along
#' with some built-ins, will be used to render \code{"module-ui.html"}.
#' The built-in functions are
#' \describe{
#' \item{ns}{shiny name-space function; should be used to generate the id for
#' inputs and outputs. This strategy avoids conflict id effectively.}
#' \item{.module_id}{a variable of the module id}
#' \item{module_title}{a function that returns the module label}
#' }
#'
#' The \code{"server.R"} has access to all the code in \code{R/} as well.
#' Therefore it is highly recommended that you write each 'UI' component
#' side-by-side with their corresponding server functions and call
#' these server functions in \code{"server.R"}.
#'
#' @examples
#'
#' library(shiny)
#' module_info()
#'
#' # load master module
#' load_module()
#'
#' # load specific module
#' module_data <- load_module(
#'   request = list(QUERY_STRING = "/?module=module_id"))
#' env <- module_data$environment
#'
#' if (interactive()){
#'
#' # get module title
#' env$module_title()
#'
#' # generate module-specific shiny id
#' env$ns("input1")
#'
#' # generate part of the UI
#' env$ui()
#'
#' }
#'
#' @export
module_info <- function(root_path = template_root(),
                        settings_file = "modules.yaml"){
  settings <- yaml::read_yaml(file.path(root_path, settings_file))
  # settings <- yaml::read_yaml('modules.yaml')
  groups <- names(settings$groups)
  groups <- groups[groups != ""]

  modules <- settings$modules
  modules_ids <- names(settings$modules)

  groups <- unique(groups)
  group_level <- factor(groups, levels = groups, ordered = TRUE)

  module_tbl <- do.call('rbind', lapply(modules_ids, function(mid){
    x <- modules[[mid]]
    y <- x[!names(x) %in% c('order', 'group', 'label', 'icon', 'badge', 'module', 'hidden')]
    y$module <- mid
    url <- httr2::url_modify("https://dipterix.org/?module=", query = y)
    if (length(x$group) == 1 && x$group %in% group_level) {
      x$group <- group_level[group_level == x$group][[1]]
    } else {
      x$group <- NA
    }
    data.frame(
      id = mid,
      group = x$group,
      label = ifelse(length(x$label) == 1, x$label, ""),
      icon = ifelse(length(x$icon) == 1, x$icon, ""),
      badge = ifelse(length(x$badge) == 1, x$badge, ""),
      url = gsub("^[^\\?]+", "/", url),
      stringsAsFactors = FALSE
    )
  }))
  module_tbl
}


#' @rdname module_info
#' @description \code{current_module} returns the information of the currently
#' running module. It looks up the \code{.module_id} variable in the calling
#' environment (set automatically when a module is loaded), then retrieves
#' the corresponding row from the module table.
#' @param session shiny reactive domain; used to extract the module id from
#' the URL query string when \code{.module_id} is not found.
#' @returns \code{current_module}: a named list with \code{id}, \code{group},
#' \code{label}, \code{icon}, \code{badge}, and \code{url} of the current
#' module, or \code{NULL} if no module is active.
#' @export
current_module <- function(
    session = shiny::getDefaultReactiveDomain(),
    root_path = template_root()) {

  module_id <- NULL

  # 1. Try the calling environment's .module_id (set by load_module)
  env <- parent.frame()
  if (exists(".module_id", envir = env, inherits = TRUE)) {
    module_id <- get(".module_id", envir = env, inherits = TRUE)
  }

  # 2. Fallback: parse the session's URL query string
  if (!length(module_id) && is.environment(session)) {
    query_str <- shiny::isolate(session$clientData$url_search)
    if (length(query_str) == 1L) {
      query_list <- shiny::parseQueryString(query_str)
      module_id <- query_list$module
    }
  }

  if (!length(module_id) || !nzchar(module_id)) {
    return(NULL)
  }

  modules <- module_info(root_path = root_path)
  idx <- which(modules$id == module_id)
  if (!length(idx)) {
    return(NULL)
  }
  as.list(modules[idx[1L], ])
}


#' @rdname module_info
#' @description \code{active_module} returns a \emph{reactive} value with
#' information about the module that is currently visible in the \verb{iframe}
#' tab (or the standalone module if no \verb{iframe} manager is present).
#' Unlike \code{current_module} which is static and always returns the module
#' whose server code is running, \code{active_module} dynamically tracks
#' which module the user is looking at from any context.
#' @details
#' \code{active_module} works by reading the
#' \code{'@shidashi_active_module@'} Shiny input that is set by the
#' JavaScript front-end whenever a module tab is activated.
#' Because it accesses \code{session$rootScope()$input}, the return value
#' is reactive: when called inside an \code{observe} or \code{reactive}
#' context it will re-fire whenever the user switches modules.
#'
#' If the input has not been set yet (e.g. before any module is opened),
#' the function falls back to \code{current_module()}.
#' @returns \code{active_module}: a named list with \code{id}, \code{group},
#' \code{label}, \code{icon}, \code{badge}, and \code{url} of the
#' currently active (visible) module, or \code{NULL} if no module is active.
#' @export
active_module <- function(
    session = shiny::getDefaultReactiveDomain(),
    root_path = template_root()) {

  # Resolve root scope session
  root_session <- session
  if (is.function(session$rootScope)) {
    root_session <- session$rootScope()
  }
  if (is.null(root_session)) {
    root_session <- session
  }

  # Read the @shidashi_active_module@ input (reactive)
  active_input <- root_session$input[["@shidashi_active_module@"]]

  module_id <- NULL
  if (is.list(active_input) && length(active_input$module_id)) {
    module_id <- active_input$module_id
  } else if (is.character(active_input) && length(active_input) == 1L) {
    module_id <- active_input
  }

  if (!length(module_id) || !nzchar(module_id)) {
    # Fallback to current_module when no active module has been reported yet
    return(current_module(session = session, root_path = root_path))
  }

  modules <- module_info(root_path = root_path)
  idx <- which(modules$id == module_id)
  if (!length(idx)) {
    return(NULL)
  }
  as.list(modules[idx[1L], ])
}


load_module_resource <- function(root_path = template_root(), module_id = NULL, env = parent.frame()){
  if (length(module_id) > 1) {
    stop("length of `module_id` must not exceed one.")
  }
  root_path <- normalizePath(root_path, mustWork = TRUE)

  re <- list(
    environment = env,
    has_module = FALSE,
    root_path = root_path,
    template_path = file.path(root_path, "index.html")
  )

  module_info <- list(
    id = module_id,
    server = function(input, output, session, ...){},
    template_path = NULL
  )

  r_folder <- file.path(root_path, "R")
  if (dir.exists(r_folder)) {
    fs <- list.files(r_folder, pattern = "\\.R$", ignore.case = TRUE,
                     recursive = FALSE, include.dirs = FALSE,
                     no.. = TRUE, all.files = TRUE, full.names = TRUE)
    for (f in fs) {
      if (startsWith(basename(f), "shared-")) {
        source(f, local = env, chdir = TRUE)
      } else {
        source(f, local = env, chdir = FALSE)
      }
    }
  }

  # root_path <- 'inst/builtin-templates/bslib-bare/'
  # module_id <- "demo"
  root_agent_folder <- file.path(root_path, "agents", "tools")
  if (dir.exists(root_agent_folder)) {
    fs <- list.files(root_agent_folder, pattern = "\\.R$", ignore.case = TRUE,
                     recursive = FALSE, include.dirs = FALSE,
                     no.. = TRUE, all.files = TRUE, full.names = TRUE)
    for (f in fs) {
      source(f, local = env, chdir = TRUE)
    }
  }

  if (length(module_id) == 1) {
    module_root <- file.path(root_path, 'modules', module_id)
    module_info$template_path <- file.path(module_root, "module-ui.html")

    if (dir.exists(module_root)) {

      re$has_module <- TRUE
      env$ns <- shiny::NS(module_id)
      env$.module_id <- module_id
      env$module_title <- function(){
        modules <- module_info()
        modules$label[modules$id == module_id]
      }
      shidashi_globals <- get_shidashi_globals(env)
      shared_input_specs <- shidashi_globals$get_module_input_specs(module_id)
      shared_output_specs <- shidashi_globals$get_module_output_specs(module_id)
      wrapper_input_registry <- mcp_wrapper_input_output(
        input_specs = shared_input_specs,
        output_specs = shared_output_specs
      )
      env$.register_input <- wrapper_input_registry$input_helpers$register_input_specification
      env$.register_output <- wrapper_input_registry$input_helpers$register_output_specification
      env$.mcp_wrapper_inputs <- wrapper_input_registry$tool_generator
      current_input_table <- wrapper_input_registry$input_helpers$get_input_specification()

      r_folder <- file.path(module_root, 'R')
      if (dir.exists(r_folder)) {
        fs <- list.files(r_folder, pattern = "\\.R$", ignore.case = TRUE,
                         recursive = FALSE, include.dirs = FALSE,
                         no.. = TRUE, all.files = TRUE, full.names = TRUE)
        for (f in fs) {
          if (startsWith(basename(f), "shared-")) {
            source(f, local = env, chdir = TRUE)
          } else {
            source(f, local = env, chdir = FALSE)
          }
        }
      }

      new_input_table <- wrapper_input_registry$input_helpers$get_input_specification()
      if (nrow(new_input_table) > nrow(current_input_table)) {
        message("Registered inputs to MCP server:", appendLF = TRUE)
        print(new_input_table[, c("inputId", "update", "writable")])
      }


      # ---- Register MCP tools ----
      # read agent.yaml
      agent_conf_path <- file.path(module_root, "agents.yaml")
      if (file.exists(agent_conf_path)) {
        agent_conf <- yaml::read_yaml(agent_conf_path)
        agent_conf$parameters <- as.list(agent_conf$parameters)
        if (!length(agent_conf$parameters$system_prompt)) {
          agent_conf$parameters$system_prompt <- paste(
            "You are an R shiny expert. You have access to the shiny",
            "application via provided tools."
          )
        }
        # Top-level enabled flag: default TRUE when agents.yaml exists
        if (is.null(agent_conf$enabled)) {
          agent_conf$enabled <- TRUE
        } else {
          agent_conf$enabled <- isTRUE(agent_conf$enabled)
        }
      } else {
        # agents.yaml missing → agents disabled for this module
        agent_conf <- list(
          enabled = FALSE,
          tools = list(
            # list(
            #   name = "hello_world",
            #   category = list("exploratory"),
            #   enabled = TRUE
            # ),
            # list(
            #   name = "get_shiny_input_values",
            #   category = list("exploratory"),
            #   enabled = TRUE
            # )
          ),
          skills = list(),
          parameters = list(
            system_prompt = paste(
              "You are a helpful assistant."
            )
          )
        )
      }

      tool_names <- unlist(lapply(agent_conf$tools, "[[", "name"))
      names(agent_conf$tools) <- tool_names

      skill_names <- unlist(lapply(agent_conf$skills, "[[", "name"))
      if (length(agent_conf$skills)) {
        names(agent_conf$skills) <- skill_names
      }

      vnames <- ls(env, all.names = TRUE)
      tools <- lapply(vnames, function(vname) {
        value <- env[[vname]]
        if (!is.function(value)) { return() }
        if (inherits(value, "ellmer::ToolDef")) { return(value) }
        if (inherits(value, "shidashi_mcp_wrapper")) { return(value) }
        return(NULL)
      })

      tools <- drop_null(tools)

      # ---- Discover skill directories (Phase 4) ----
      # Per Anthropic spec, skill name == folder name. Direct lookup,
      # no iteration needed. Missing folders are silently dropped.
      skill_wrappers <- list()
      if (length(skill_names)) {
        root_skills_dir <- file.path(root_path, "agents", "skills")
        for (sname in skill_names) {
          skill_dir <- file.path(root_skills_dir, sname)
          if (file.exists(file.path(skill_dir, "SKILL.md"))) {
            skill_wrappers[[sname]] <- skill_wrapper(skill_dir)
          }
        }
      }

      # create a tool-generating function
      tool_gen_fun <- function(session) {

        tool_map <- fastmap::fastmap()
        lapply(tools, function(tool) {

          if (inherits(tool, "ellmer::ToolDef")) {
            if (tool@name %in% tool_names) {
              tool_conf <- agent_conf$tools[[tool@name]]
              tool@annotations$shidashi_enabled <- isTRUE(tool_conf$enabled)
              tool@annotations$shidashi_category <- as.character(tool_conf$category)
              tool@annotations$shidashi_namespace <- session$ns(NULL)
              old_name <- tool@name
              tool@name <- sprintf("tool__%s__%s", session$ns(NULL), tool@name)
              tool_map$set(old_name, tool)
            }
          } else {
            # generator
            toolset <- tool(session = session)
            if (inherits(toolset, "ellmer::ToolDef")) {
              toolset <- list(toolset)
            }
            lapply(toolset, function(tool) {
              if (tool@name %in% tool_names) {
                tool_conf <- agent_conf$tools[[tool@name]]
                tool@annotations$shidashi_enabled <- isTRUE(tool_conf$enabled)
                tool@annotations$shidashi_category <- as.character(tool_conf$category)
                tool@annotations$shidashi_namespace <- session$ns(NULL)
                old_name <- tool@name
                tool@name <- sprintf("tool__%s__%s", session$ns(NULL), tool@name)
                tool_map$set(tool@name, tool)
              }
            })
          }

        })

        # ---- Process skill wrappers (Phase 4) ----
        lapply(names(skill_wrappers), function(sname) {
          wrapper <- skill_wrappers[[sname]]
          skill_tool <- tryCatch(
            wrapper(),
            error = function(e) {
              warning("Failed to create skill tool '", sname, "': ",
                      conditionMessage(e))
              NULL
            }
          )
          if (inherits(skill_tool, "ellmer::ToolDef")) {
            skill_conf <- agent_conf$skills[[sname]]
            skill_tool@annotations$shidashi_enabled <-
              isTRUE(skill_conf$enabled)
            skill_tool@annotations$shidashi_category <-
              c("skill", as.character(skill_conf$category))
            skill_tool@annotations$shidashi_namespace <- session$ns(NULL)
            skill_tool@name <- sprintf("skill__%s__%s",
                                       session$ns(NULL), sname)
            tool_map$set(skill_tool@name, skill_tool)
          }
        })

        tool_map

      }

      env$.mcptools_maker <- tool_gen_fun
      # Store agent config in module env for chatbot_ui / back_top_button

      module_handler <- file.path(root_path, 'modules', module_id, 'server.R')
      if (file.exists(module_handler)) {
        # server_env <- new.env(parent = env)
        server_env <- env
        server_source <- source(module_handler, local = server_env)

        server_function <- server_source$value
        if (!is.function(server_function)) {
          server_function <- server_env$server
        }

        if (!is.function(server_function)) {
          stop("Module `", module_id, "` has server.R, but cannot detect server function.")
        }

        # inject to body
        agent_enabled <- isTRUE(agent_conf$enabled)
        body(server_function) <- bquote({
          local({
            shidashi <- asNamespace("shidashi")
            shidashi$register_session_mcp(session = session)
            registry <- shidashi$mcp_session_registry()
            entry <- registry$get(session$token)
            tools <- .mcptools_maker(session)
            entry$tools <- tools$as_list()
            registry$set(session$token, entry)

            # Initialize chatbot server if agents are enabled for this module
            if (.(isTRUE(agent_conf$enabled))) {
              shidashi$chatbot_server(
                input, output, session,
                agent_conf = .(agent_conf)
              )
            }


          })

          .(body(server_function))
        })

        module_info$server <- server_function
      }

      # make sure `ns` and `.module_id` are consistent
      env$ns <- shiny::NS(module_id)
      env$.module_id <- module_id

    }
  }

  re$module <- module_info
  re
}

#' @rdname module_info
#' @export
load_module <- function(
  root_path = template_root(),
  request = list(QUERY_STRING = "/"),
  env = parent.frame()){

  force(env)
  query_str <- request$QUERY_STRING
  if (length(query_str) != 1) {
    query_str <- '/'
  }
  query_list <- shiny::parseQueryString(query_str)
  module_id <- query_list$module
  shared_id <- query_list$shared_id
  shared_id <- tolower(shared_id)
  shared_id <- gsub("[^a-z0-9_]", "", shared_id)
  if (length(shared_id) != 1 || nchar(shared_id) ) {
    shared_id <- rand_string(26)
  }

  env$.request <- request
  env$.shared_id <- shared_id
  load_module_resource(root_path, module_id, env)
}
