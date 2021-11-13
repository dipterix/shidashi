#' @title Obtain the module information
#' @param root_path the root path of the website project
#' @param settings_file the settings file containing the module information
#' @param request 'HTTP' request string
#' @param env environment to load module variables into
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
#' # get module title
#' env$module_title()
#'
#' # generate module-specific shiny id
#' env$ns("input1")
#'
#' # generate part of the UI
#' env$ui()
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
    y <- x[!names(x) %in% c('order', 'group', 'label', 'icon', 'badge', 'module')]
    y$module <- mid
    url <- httr::modify_url("/?module=", query = y)
    if(length(x$group) == 1 && x$group %in% group_level){
      x$group <- group_level[group_level == x$group][[1]]
    } else {
      x$group <- NA
    }
    data.frame(
      id = mid,
      order = x$order,
      group = x$group,
      label = x$label,
      icon = ifelse(length(x$icon) == 1, x$icon, ""),
      badge = ifelse(length(x$badge) == 1, x$badge, ""),
      url = gsub("^[^\\?]+", "/", url),
      stringsAsFactors = FALSE
    )
  }))
  module_tbl
}


load_module_resource <- function(root_path = template_root(), module_id = NULL, env = parent.frame()){
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
  if(dir.exists(r_folder)){
    fs <- list.files(r_folder, pattern = "\\.R$", ignore.case = TRUE,
                     recursive = FALSE, include.dirs = FALSE,
                     no.. = TRUE, all.files = TRUE, full.names = TRUE)
    for(f in fs){
      source(f, local = env)
    }
  }

  if(length(module_id)){
    if(length(module_id) > 1){
      stop("length of `module_id` must not exceed one.")
    }
    module_root <- file.path(root_path, 'modules', module_id)
    module_info$template_path <- file.path(module_root, "module-ui.html")

    if(dir.exists(module_root)){

      re$has_module <- TRUE
      env$ns <- shiny::NS(module_id)
      env$.module_id <- module_id
      env$module_title <- function(){
        modules <- module_info()
        modules$label[modules$id == module_id]
      }

      r_folder <- file.path(module_root, 'R')
      if(dir.exists(r_folder)){
        fs <- list.files(r_folder, pattern = "\\.R$", ignore.case = TRUE,
                         recursive = FALSE, include.dirs = FALSE,
                         no.. = TRUE, all.files = TRUE, full.names = TRUE)
        for(f in fs){
          source(f, local = env)
        }
      }

      module_handler <- file.path(root_path, 'modules', module_id, 'server.R')
      if(file.exists(module_handler)){
        # server_env <- new.env(parent = env)
        server_env <- env
        server_source <- source(module_handler, local = server_env)

        server_function <- server_source$value
        if(!is.function(server_function)){
          server_function <- server_env$server
        }

        if(!is.function(server_function)){
          stop("Module `", module_id, "` has server.R, but cannot detect server function.")
        }
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
  if(length(query_str) != 1) {
    query_str <- '/'
  }
  query_list <- httr::parse_url(query_str)
  module_id <- query_list$query$module
  shared_id <- query_list$query$shared_id
  shared_id <- tolower(shared_id)
  shared_id <- gsub("[^a-z0-9_]", "", shared_id)
  if(length(shared_id) != 1 || nchar(shared_id) ){
    shared_id <- rand_string(26)
  }

  env$.request <- request
  env$.shared_id <- shared_id
  load_module_resource(root_path, module_id, env)
}

