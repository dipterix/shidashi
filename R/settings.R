#' @title Configure template options that are shared across the sessions
#' @param ... key-value pair to set options
#' @param name character, key of the value
#' @param default default value if the key is missing
#' @return \code{template_settings_get} returns the values represented by the
#' corresponding keys, or the default value if key is missing.
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
#' @export
template_settings_set <- template_settings$set

#' @rdname template_settings
#' @export
template_settings_get <- template_settings$get

#' @rdname template_settings
#' @export
template_root <- function(){
  path <- template_settings$get(
    name = 'root_path',
    default = NULL
  )
  if(!length(path)) {
    if(template_settings$get("dev.debug", FALSE)){
      path <- 'inst/buildin-templates/AdminLTE3/'
    } else {
      path <- file.path(R_user_dir('shidashi', which = "data"), "AdminLTE3")
      if(!dir.exists(path)){
        path <- file.path(R_user_dir('shidashi', which = "data"), "AdminLTE3-bare")
        create_barebone(path)
      }
    }

  }
  normalizePath(path, mustWork = FALSE)
}
