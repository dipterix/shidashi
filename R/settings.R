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
#' @export
template_settings_set <- template_settings$set

#' @rdname template_settings
#' @export
template_settings_get <- template_settings$get

#' @rdname template_settings
#' @export
download_builtin_templates <- function(){
  path <- file.path(R_user_dir('shidashi', which = "data"), "AdminLTE3")
  unlink(path, recursive = TRUE, force = TRUE)
  create_project(path, user = "dipterix", theme = "AdminLTE3")
}

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
      if(isTRUE(template_settings$get("update_defaults", FALSE))){
        download_builtin_templates()
        template_settings$set("update_defaults" = FALSE)
      }
      if(!dir.exists(path)){
        stop(
          "No template found. Please set correct `root_path` if you haven't done so via:\n",
          "  template_settings_set(root_path = '...')\n\n",
          "Alternatively, you could download the builtin demo via:\n",
          "  download_builtin_templates()"
        )
      }
    }

  }
  normalizePath(path, mustWork = FALSE)
}
