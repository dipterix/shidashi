#' @export
template_settings <- local({
  map <- fastmap::fastmap()
  list(
    get = function(name, default = NULL){
      map$get(name, missing = default)
    },
    set = function(...){
      map$mset(...)
    },
    list = function(){
      map$as_list()
    }
  )
})

#' @export
template_root <- function(){
  template_settings$get(
    name = 'root_path',
    default = "inst/templates/AdminLTE/"
  )
}

#' @export
template_render <- function(
  template = template_root(),
  ...,
  launch_browser = TRUE,
  as_job = TRUE,
  test_mode = getOption("shiny.testmode", FALSE)
){
  if(!dir.exists(template)){
    stop("`template` cannot be found: ", template)
  }
  template <- normalizePath(template, mustWork = TRUE)

  if(test_mode){
    tempdir <- template
  } else {
    tempdir <- tempfile(pattern = "shiny_template_")
    if(dir.exists(tempdir)){
      unlink(tempdir, recursive = TRUE, force = TRUE)
    }
    dir.create(tempdir, showWarnings = FALSE, recursive = TRUE)
    file.copy(list.files(template, all.files = TRUE, full.names = TRUE, no.. = TRUE), tempdir, recursive = TRUE, overwrite = TRUE)
  }



  writeLines(
    deparse(bquote({
      shinytemplates::template_settings$set('root_path' = .(tempdir))
      shinytemplates::adminlte_ui()
    })),
    file.path(tempdir, "ui.R")
  )

  if(!as_job || system.file(package = 'rstudioapi') == '' ||
     !rstudioapi::isAvailable(version_needed = "1.4.1717",
                              child_ok = FALSE)){

    shinytemplates::template_settings$set('root_path' = tempdir)
    shiny::runApp(appDir = tempdir, launch.browser = launch_browser, test.mode = test_mode, ...)
  } else {
    script <- file.path(tempdir, "_rs_job.R")
    args <- list(
      ...,
      launch.browser = launch_browser,
      test.mode = test_mode,
      appDir = tempdir
    )
    writeLines(
      con = script,
      deparse(bquote({
        shinytemplates::template_settings$set('root_path' = .(tempdir))
        do.call(shiny::runApp, .(args))
      }))
    )
    rstudioapi::jobRunScript(
      path = script, workingDir = tempdir,
      name = basename(template)
    )
  }

}

#' @export
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

#' @export
include_view <- function(file, ..., root_path = template_root()){
  tryCatch({
    file <- normalizePath(file.path(root_path, 'views', file), mustWork = TRUE)
  }, error = function(e){
    stop(call. = NULL, "Cannot find views/", file)
  })

  shiny::htmlTemplate(file, ..., document_ = FALSE)
}



