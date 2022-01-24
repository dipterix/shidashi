#' @title Download 'shidashi' templates from 'Github'
#' @param path the path to create 'shidashi' project
#' @param user 'Github' user name
#' @param theme the theme to download
#' @param repo repository if the name is other than \code{'shidashi-templates'}
#' @param branch branch name if other than \code{'main'} or \code{'master'}
#' @param ... ignored
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
#' @export
use_template <- function(
  path, user = "dipterix", theme = "AdminLTE3",
  repo = "shidashi-templates", branch = "main", ...
){

  # ensure path exists
  dir.create(path, recursive = TRUE, showWarnings = FALSE)

  # Download template
  temppath <- tempfile()
  tempzip <- paste0(temppath, ".zip")
  if(file.exists(tempzip)){
    unlink(tempzip)
  }
  if(dir.exists(temppath)){
    unlink(temppath, recursive = TRUE, force = TRUE)
  }
  old <- options()
  on.exit({
    options(old)
    unlink(tempzip)
    unlink(temppath, recursive = TRUE, force = TRUE)
  })

  options(timeout = 10000)

  url <- sprintf("https://github.com/%s/%s/archive/%s.zip", user, repo, branch)
  if(branch %in% c("main", "master")){
    tryCatch({
      suppressWarnings({
        utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
      })
    }, error = function(e){
      old_branch <- branch
      if(branch == "main"){
        branch <<- "master"
      } else {
        branch <<- "main"
      }
      message("Branch `", old_branch, "` does not have zip file, switching to `", branch, "`.", appendLF = TRUE)
      url <- sprintf("https://github.com/%s/%s/archive/%s.zip", user, repo, branch)
      utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
    })

  } else {
    utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
  }


  # url <- "https://github.com/dipterix/shidashi-templates/archive/refs/heads/master.zip"
  # utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
  utils::unzip(tempzip, exdir = temppath)

  folder_name <- sprintf("%s-%s", repo, branch)
  root <- file.path(temppath, folder_name)
  if(!dir.exists(root)){
    stop("Cannot find branch folder `", folder_name, "`. Please report this issue to \n\thttps://github.com/dipterix/shidashi/issues")
  }
  project_dir <- normalizePath(file.path(root, theme), mustWork = TRUE)

  fs <- list.files(project_dir, all.files = FALSE, recursive = FALSE, full.names = TRUE, include.dirs = TRUE, no.. = TRUE)

  if(!length(fs)){
    if(theme == ""){
      stop("Empty sub-module repository. Your theme contains no file. Abort.")
    }
    # This could be a sub-module, parse .gitmodules
    submodule_spath <- file.path(root, ".gitmodules")
    if(!file.exists(submodule_spath)){
      stop("Theme `", theme, "` exists but it's empty. Abort.")
    }
    settings <- readLines(submodule_spath)
    # Find submodule
    sel <- startsWith(settings, sprintf("[submodule \"%s\"]", theme))
    if(!any(sel)){
      stop("Theme `", theme, "` is empty. I guess it's a git submodule. However, I cannot locate it in the `.gitmodules` file.")
    }
    settings <- settings[seq(which(sel), length(settings))]
    sel <- which(grepl("\\[submodule", settings))
    if(length(sel) > 1){
      settings <- settings[seq(sel[[1]], sel[[2]] - 1)]
    }
    sel <- grepl("^[^a-zA-Z0-9]url[ =]", settings)
    if(!any(sel)){
      stop("Theme `", theme, "` is a git submodule. However, I cannot locate the URL.")
    }
    url <- settings[sel][[1]]
    if(grepl("url[ =]+http", url)){
      url <- strsplit(url, split = "/")[[1]]
      uname <- url[[length(url) - 1]]
      repo <- url[[length(url)]]
      if(grepl("@", repo)){
        tmp <- strsplit(repo, "@")[[1]]
        repo <- tmp[[1]]
        branch <- tmp[[2]]
      } else {
        sel <- grepl("^[^a-zA-Z0-9]branch[ =]", settings)
        if(any(sel)){
          branch <- settings[sel][[1]]
          branch <- strsplit(branch, "=")[[1]][[2]]
          branch <- sub("[ \t]+", "", branch)
        } else {
          branch <- "main"
        }
      }
    } else if (grepl("url[ =]+git@", url)){
      url <- strsplit(url, split = ":")[[1]]
      url <- unlist(strsplit(url, split = "/"))
      uname <- url[[length(url) - 1]]
      repo <- url[[length(url)]]
      if(grepl("@", repo)){
        tmp <- strsplit(repo, "@")[[1]]
        repo <- tmp[[1]]
        branch <- tmp[[2]]
      } else {
        sel <- grepl("^[^a-zA-Z0-9]branch[ =]", settings)
        if(any(sel)){
          branch <- settings[sel][[1]]
          branch <- strsplit(branch, "=")[[1]][[2]]
          branch <- sub("[ \t]+", "", branch)
        } else {
          branch <- "main"
        }
      }
      if(endsWith(repo, ".git")){
        repo <- sub("\\.git$", "", repo)
      }
    } else {
      stop("Theme `", theme, "` is a git submodule. However, I cannot parse the URL:\n", url)
    }

    re <- use_template(path = path, user = uname, theme = "",
                       repo = repo, branch = branch, ...)
    return(re)
    # https://github.com/dipterix/rave-pipelines/archive/578c8644b2b67623b7efd138a1e5340fc068e725.zip
    # url <- sprintf("https://github.com/%s/%s/archive/%s.zip", uname, repo, branch)
    # unlink(tempzip)
    # if(branch %in% c("main", "master")){
    #   tryCatch({
    #     utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
    #   }, error = function(e){
    #     if(branch == "main"){
    #       branch <- "master"
    #     } else {
    #       branch <- "main"
    #     }
    #     url <- sprintf("https://github.com/%s/%s/archive/%s1.zip", uname, repo, branch)
    #     utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
    #   })
    #
    # } else {
    #   utils::download.file(url, destfile = tempzip, cacheOK = FALSE)
    # }
    #
    # unlink(temppath, recursive = TRUE)
    # utils::unzip(tempzip, exdir = temppath)


  }


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

