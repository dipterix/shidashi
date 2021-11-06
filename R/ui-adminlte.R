#' @export
adminlte_ui <- function(root_path = template_root()){
  function(req){
    # req <- (list(QUERY_STRING = "/"))
    # root_path <- "/Users/dipterix/Dropbox/projects/shinytemplates/inst/templates/AdminLTE"

    # tryCatch({
      resource <- load_module(root_path = root_path, request = req)
      env <- new.env(parent = resource$environment)

      if(resource$has_module){
        # load module UI
        template_path <- resource$module$template_path
      } else {
        if(!length(resource$module$id)){
          # load overall UI
          template_path <- resource$template_path
        } else {
          # 404
          template_path <- file.path(root_path, 'views', '404.html')
          if(!file.exists(template_path)){
            return("Page not found (404)")
          }
        }
      }

      `@args` <- as.list(resource$environment, all.names = TRUE)
      `@args`$filename <- template_path
      env$`@args` <- `@args`

      return(with(env, {
        do.call(shiny::htmlTemplate, `@args`)
      }))
    # }, error = function(e){
    #   module_template <- file.path(root_path, 'views', '500.html')
    #   error <- shiny::pre(paste(
    #     sep = "\n",
    #     "Error message:",
    #     e$message
    #   ))
    #   if(file.exists(module_template)){
    #
    #     return(shiny::htmlTemplate(module_template, error = error, req = req))
    #   } else {
    #     return(paste("Internal error: <br/>", error))
    #   }
    # })

  }

}

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

#' @export
adminlte_sidebar <- function(root_path = template_root(),
                             settings_file = "modules.yaml",
                             shared_id = rand_string(26)){
  settings <- yaml::read_yaml(file.path(root_path, settings_file))
  # settings <- yaml::read_yaml('modules.yaml')
  groups <- settings$groups
  group_icons <- sapply(groups, function(x){ ifelse(length(x$icon) == 1, x$icon, "") })
  group_badge <- sapply(groups, function(x){ ifelse(length(x$badge) == 1, x$badge, "") })
  groups <- names(groups)
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
    y$shared_id <- shared_id
    url <- httr::modify_url("/?module=", query = y)
    if(length(x$group) == 1 && x$group %in% group_level){
      x$group <- group_level[group_level == x$group][[1]]
    } else {
      x$group <- NA
    }
    order <- x$order
    if(!length(order) || is.na(order)){
      order <- 9999L
    }
    data.frame(
      id = mid,
      order = order,
      group = x$group,
      label = x$label,
      icon = ifelse(length(x$icon) == 1, x$icon, ""),
      badge = ifelse(length(x$badge) == 1, x$badge, ""),
      url = gsub("^[^\\?]+", "/", url),
      stringsAsFactors = FALSE
    )
  }))

  if(nrow(module_tbl)){
    max_order <- max(c(module_tbl$order, 10000), na.rm = TRUE) + 1
    # group could be NA, resulting in warning
    suppressWarnings({
      module_tbl <- module_tbl[
        order(as.integer(module_tbl$group) * max_order + module_tbl$order),
      ]
    })
  }

  shiny::tagList(
    lapply(seq_along(groups), function(ii){
      group <- groups[[ii]]
      sub <- module_tbl[!is.na(module_tbl$group) & module_tbl$group == group, ]
      if(!nrow(sub)){ return(NULL) }
      menu <- lapply(seq_len(nrow(sub)), function(ii){
        x <- sub[ii, ]
        menu_item(text = x$label, icon = x$icon, href = x$url, badge = x$badge)
      })
      menu_item_dropdown(text = group, .list = menu, icon = group_icons[[ii]], badge = group_badge[[ii]])
    }),
    local({
      sub <- module_tbl[is.na(module_tbl$group), ]
      if(!nrow(sub)){ return(NULL) }
      lapply(seq_len(nrow(sub)), function(ii){
        x <- sub[ii, ]
        menu_item(text = x$label, icon = x$icon, href = x$url, badge = x$badge)
      })
    })
  )
}
