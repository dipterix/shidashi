#' @title Download 'shidashi' templates from 'Github'
#' @param path the path to create 'shidashi' project
#' @param name 'Github' user name
#' @param theme the theme to download
#' @return the target project path
#' @details To publish a 'shidashi' template, create a 'Github' repository
#' called \code{'shidashi-templates'}, or fork the \href{https://github.com/dipterix/shidashi-templates}{built-in templates}. The \code{theme} is the sub-folder
#' of the template repository.
#'
#' An easy way to use a template in your project is through the 'RStudio'
#' project widget. In the 'RStudio' navigation bar, go to "File" menu,
#' click on the "New Project..." button, select the "Create a new project"
#' option, and find the item that creates 'shidashi' templates. Use the
#' widget to set up template directory.
#'
use_template <- function(
  path, user = "dipterix", theme = "AdminLTE3", ...){
  # ensure path exists
  dir.create(path, recursive = TRUE, showWarnings = FALSE)

  # Download template
  temppath <- tempfile()
  tempzip <- paste0(temppath, ".zip")
  timeout <- getOption('timeout', 60L)
  on.exit({
    options(timeout = timeout)
    unlink(tempzip)
    unlink(temppath, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  options(timeout = 10000)
  url <- "https://github.com/dipterix/shidashi-templates/archive/refs/heads/master.zip"
  utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
  utils::unzip(tempzip, exdir = temppath)

  root <- file.path(temppath, "shidashi-templates-master")
  if(!dir.exists(root)){
    root <- temppath
  }
  project_dir <- normalizePath(file.path(root, theme), mustWork = TRUE)

  fs <- list.files(project_dir, all.files = FALSE, recursive = FALSE, full.names = TRUE, include.dirs = TRUE, no.. = TRUE)

  file.copy(fs, path, overwrite = TRUE, recursive = TRUE, copy.date = TRUE)

  # Add RStudio start-up script
  # dput(deparse(quote({
  #   try({
  #     shidashi::template_settings$set(root_path = normalizePath("."))
  #   }, silent = TRUE)
  # })))

  writeLines(
    c(
      "{",
      "    try({",
      "        shidashi::template_settings$set(root_path = normalizePath(\".\"))",
      "    }, silent = TRUE)",
      "}"
    ),
    con = file.path(path, ".Rprofile")
  )

  writeLines(c(
    "library(shidashi)\n",
    "# Render this project",
    sprintf("shidashi::template_settings$set(root_path = '%s')\n", normalizePath(path)),
    "# Render project",
    "shidashi::render(host = '127.0.0.1', port = 8310L)"
  ), con = file.path(path, "start.R"))

  invisible(normalizePath(path))
}

