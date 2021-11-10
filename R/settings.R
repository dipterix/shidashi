#' @title Configure template options that are shared across the sessions
#' @param ... key-value pair to set options
#' @param name character, key of the value
#' @param default default value if the key is missing
#' @details The settings is designed to store static key-value pairs that
#' are shared across the sessions. The most important key is
#' \code{"root_path"}, which should be a path pointing to the template
#' folder.
#' @examples
#'
#' # Get current website root path
#'
#' template_root()
#'
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

#' @rdname template_settings
template_settings_set <- template_settings$set

#' @rdname template_settings
template_settings_get <- template_settings$get

#' @rdname template_settings
#' @export
template_root <- function(){
  path <- template_settings$get(
    name = 'root_path',
    default = NULL
  )
  if(!length(path)) {
    path <- tools::R_user_dir('shidashi', which = "data")
    if(!dir.exists(file.path(path, "template"))){
      dir.create(path, showWarnings = FALSE, recursive = TRUE)
      file.copy(
        from = system.file('template', package = "shidashi"),
        to = path, recursive = TRUE, overwrite = TRUE,
        copy.date = TRUE
      )
    }
    path <- file.path(path, "template")
  }
  normalizePath(path, mustWork = FALSE)
}
