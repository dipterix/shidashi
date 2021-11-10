#' @title Obtain the module information
#' @param root_path the root path of the website project
#' @param settings_file the settings file containing the module information
#' @export
module_info <- function(root_path = template_root(),
                        settings_file = "modules.yaml"){
  settings <- yaml::read_yaml(file.path(root_path, settings_file))
  # settings <- yaml::read_yaml('modules.yaml')
  groups <- names(settings$groups)
  groups <- gsub(" ", "", groups)
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
