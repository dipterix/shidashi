

#' @export
template_render <- function(
  root_path = template_root(),
  ...,
  launch_browser = TRUE,
  as_job = TRUE,
  test_mode = getOption("shiny.testmode", FALSE)
){
  if(!dir.exists(root_path)){
    stop("`root_path` cannot be found: ", root_path)
  }
  root_path <- normalizePath(root_path, mustWork = TRUE)

  if(test_mode){
    tempdir <- root_path
  } else {
    tempdir <- tempfile(pattern = "shiny_template_")
    if(dir.exists(tempdir)){
      unlink(tempdir, recursive = TRUE, force = TRUE)
    }
    dir.create(tempdir, showWarnings = FALSE, recursive = TRUE)
    file.copy(list.files(root_path, all.files = TRUE, full.names = TRUE, no.. = TRUE), tempdir, recursive = TRUE, overwrite = TRUE)
  }



  writeLines(
    deparse(bquote({
      shidashi::template_settings$set('root_path' = .(tempdir))
      shidashi::adminlte_ui()
    })),
    file.path(tempdir, "ui.R")
  )

  if(!as_job || system.file(package = 'rstudioapi') == '' ||
     !rstudioapi::isAvailable(version_needed = "1.4.1717",
                              child_ok = FALSE)){

    shidashi::template_settings$set('root_path' = tempdir)
    shiny::runApp(appDir = tempdir, launch.browser = launch_browser, test.mode = test_mode, ...)
  } else {
    script <- file.path(tempdir, "_rs_job.R")
    args <- list(
      ...,
      launch.browser = launch_browser,
      test.mode = test_mode,
      appDir = tempdir
    )
    call <- as.call(list(
      quote(shiny::runApp),
      ...,
      launch.browser = launch_browser,
      test.mode = test_mode,
      appDir = tempdir
    ))
    s <- sprintf("shidashi::template_settings$set('root_path' = '%s')", tempdir)
    s <- c(s, deparse(call))
    writeLines(
      con = script,
      s
    )
    rstudioapi::jobRunScript(
      path = script, workingDir = tempdir,
      name = basename(root_path)
    )
  }

}

#' @export
include_view <- function(file, ..., .env = parent.frame(),
                         .root_path = template_root()){
  tryCatch({
    file <- normalizePath(file.path(.root_path, 'views', file),
                          mustWork = TRUE)
  }, error = function(e){
    stop(call. = NULL, "Cannot find views/", file)
  })
  list2env(list(.env = .env), envir=.GlobalEnv)
  args <- NULL
  if(is.environment(.env$env)) {
    args <- get0("@args", envir = .env$env, ifnotfound = NULL)
  }
  if(!is.list(args)) {
    args <- as.list(.env)
  }
  # more_args <- list(...)
  # for(nm in names(more_args)){
  #   if(nm != ""){
  #     args[[nm]] <- more_args[[nm]]
  #   }
  # }
  argnames <- names(args)
  args <- args[!argnames %in% c("headContent", "suppressDependencies", "filename", "document_", "text_")]
  call <- as.call(c(
    list(quote(shiny::htmlTemplate),
         filename = file,
         document_ = FALSE),
    args
  ))
  return(eval(call, envir = .env))
  # shiny::htmlTemplate(file, ..., document_ = FALSE)
}



