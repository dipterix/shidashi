#' @name adminlte
#' @title Generates 'AdminLTE' theme-related 'HTML' tags
#' @description These functions should be called in 'HTML' templates.
#' Please see vignettes for details.
#' @param root_path the root path of the website project; see
#' \code{\link{template_settings}}
#' @param settings_file the settings file containing the module information
#' @param shared_id a shared identification by session to synchronize the
#' inputs; assigned internally.
#' @return 'HTML' tags
#' @export
adminlte_ui <- function(root_path = template_root()){
  function(req){

    tryCatch({
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
      call <- as.call(c(list(quote(shiny::htmlTemplate)), `@args`))
      return(eval(call, envir = env))
    }, error = function(e){
      module_template <- file.path(root_path, 'views', '500.html')
      error <- shiny::pre(
        style = "word-wrap: break-word; white-space: break-spaces;",
        paste(
          sep = "\n",
          "Error message:",
          e$message,
          "Traceback:",
          paste(utils::capture.output({
            traceback(e)
          }), collapse = "\n")
        )
      )
      if(file.exists(module_template)){

        return(shiny::htmlTemplate(module_template, error = error, req = req))
      } else {
        return(paste("Internal error: <br/>", error))
      }
    })

  }

}


#' @rdname adminlte
#' @export
adminlte_sidebar <- function(root_path = template_root(),
                             settings_file = "modules.yaml",
                             shared_id = rand_string(26)){
  settings <- yaml::read_yaml(file.path(root_path, settings_file))
  # settings <- yaml::read_yaml('modules.yaml')

  divider <- settings$divider
  if(length(divider)){
    divider <- data.frame(
      name = names(divider),
      order = sapply(divider, function(x){ if(isTRUE(is.numeric(x$order))){x$order}else{NA} })
    )
    divider <- divider[!is.na(divider$order), ]
  }
  if(!length(divider) || !nrow(divider)){
    divider <- data.frame(name = "END", order = Inf)
  }

  groups <- settings$groups
  if(length(groups)){
    groups <- groups[names(groups) != '']
  }
  group_icons <- sapply(groups, function(x){ ifelse(length(x$icon) == 1, x$icon, "") })
  group_badge <- sapply(groups, function(x){ ifelse(length(x$badge) == 1, x$badge, "") })
  group_order <- sapply(groups, function(x){ ifelse(length(x$order) == 1, x$order, NA) })
  group_open <- sapply(groups, function(x){ isTRUE(x$open) })
  groups <- names(groups)

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
    order <- x$order
    if(!length(order) || is.na(order)){
      order <- 9999L
    }

    if(length(x$group) == 1 && x$group %in% group_level){
      x$group <- group_level[group_level == x$group][[1]]
      renderOrder <- group_order[group_level == x$group][[1]] + order / 10000
    } else {
      x$group <- NA
      renderOrder <- order
    }


    data.frame(
      id = mid,
      order = order,
      renderOrder = renderOrder,
      group = x$group,
      label = ifelse(length(x$label) == 1, x$label, "No Label"),
      icon = ifelse(length(x$icon) == 1, x$icon, ""),
      badge = ifelse(length(x$badge) == 1, x$badge, ""),
      url = gsub("^[^\\?]+", "/", url),
      stringsAsFactors = FALSE
    )
  }))

  if(nrow(module_tbl)){
    max_order <- max(c(module_tbl$renderOrder, 10000), na.rm = TRUE) + 1
    # group could be NA, resulting in warning
    suppressWarnings({
      module_tbl <- module_tbl[
        order(module_tbl$renderOrder),
      ]
    })
  }

  side_bar <- list()
  ignore_group <- NULL
  last_order <- -Inf

  for(i in seq_len(nrow(module_tbl))){
    x <- module_tbl[i, ]

    current_order <- x$renderOrder

    divide_item <- divider[divider$order <= current_order & divider$order > last_order,]
    if(nrow(divide_item)){
      for(j in seq_len(nrow(divide_item))){
        tmp <- divide_item[j, ]
        side_bar[[length(side_bar) + 1]] <- shiny::tags$li(
          class="nav-header nav-divider",
          shiny::span(
            tmp$name
          )
        )
      }
    }
    last_order <- current_order

    if(is.na(x$group)){
      item <- menu_item(text = x$label, icon = x$icon, href = x$url, badge = x$badge)
      side_bar[[length(side_bar) + 1]] <- item
    } else if(!x$group %in% ignore_group){

      # add group
      group <- x$group
      ignore_group <- c(ignore_group, group)
      sub <- module_tbl[!is.na(module_tbl$group) & module_tbl$group == group, ]
      if(nrow(sub)){

        menu <- lapply(seq_len(nrow(sub)), function(ii){
          x <- sub[ii, ]
          menu_item(text = x$label, icon = x$icon, href = x$url, badge = x$badge)
        })
        sel <- which(groups %in% group)[[1]]
        item <- menu_item_dropdown(text = group, .list = menu,
                                   icon = group_icons[sel],
                                   badge = group_badge[sel],
                                   active = group_open[sel])
        side_bar[[length(side_bar) + 1]] <- item
      }

    }
  }

  shiny::tagList(side_bar)

  # shiny::tagList(
  #   lapply(seq_along(groups), function(ii){
  #     group <- groups[[ii]]
  #     sub <- module_tbl[!is.na(module_tbl$group) & module_tbl$group == group, ]
  #     if(!nrow(sub)){ return(NULL) }
  #     menu <- lapply(seq_len(nrow(sub)), function(ii){
  #       x <- sub[ii, ]
  #       menu_item(text = x$label, icon = x$icon, href = x$url, badge = x$badge)
  #     })
  #     menu_item_dropdown(text = group, .list = menu, icon = group_icons[[ii]], badge = group_badge[[ii]])
  #   }),
  #   local({
  #     sub <- module_tbl[is.na(module_tbl$group), ]
  #     if(!nrow(sub)){ return(NULL) }
  #     lapply(seq_len(nrow(sub)), function(ii){
  #       x <- sub[ii, ]
  #       menu_item(text = x$label, icon = x$icon, href = x$url, badge = x$badge)
  #     })
  #   })
  # )
}
