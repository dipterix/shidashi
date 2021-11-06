card_tabset_header <- function(id_tabset, index, title, active = FALSE){
  shiny::tags$li(
    class = "nav-item nav-tab-header",
    shiny::a(
      class = ifelse(active, "nav-link active", "nav-link"),
      id = sprintf("%s-%s-tab", id_tabset, index),
      'data-toggle' = "pill",
      href = sprintf("#%s-%s", id_tabset, index),
      role = "tab",
      "aria-controls" = sprintf("%s-%s", id_tabset, index),
      "aria-selected" = ifelse(active, "true", "false"),
      "tab-index" = index,
      title
    )
  )
}

card_tabset_content <- function(id_tabset, index, active, ...){
  shiny::div(
    class = ifelse(active, "tab-pane fade active show", "tab-pane fade"),
    id = sprintf("%s-%s", id_tabset, index),
    role = "tabpanel",
    "aria-labelledby" = sprintf("%s-%s-tab", id_tabset, index),
    "tab-index" = index,
    ...
  )
}

#' @export
card_tabset <- function(
  ..., inputId = rand_string(), title = NULL,
  names = NULL, active = NULL, tools = NULL, footer = NULL,
  class = "", class_header = "", class_body = "", class_foot = ""){

  call_ <- match.call()

  if(grepl("[^a-zA-Z0-9_-]", inputId)){
    stop("card_tabset: invalid `inputId`, can only have letters, digits, '-', or '_'.")
  }

  tabs <- list(...)
  ntabs <- length(tabs)
  if(!length(names)){
    names <- names(tabs)
  }
  if(length(names) != ntabs){
    stop("card_tabset: `names` must have the same length as tab elements")
  }

  if(length(title) == 1){
    title <- shiny::tags$li(
      class="pt-2 px-3",
      shiny::h4(class="card-title", title)
    )
  }
  if(length(active)){
    active <- active[[1]]
  } else if(length(names)){
    active <- names[[1]]
  }

  if(length(tools)){
    tools <- shiny::tags$li(class = "nav-item ml-auto",
                            shiny::div(class = "card-tools",
                                       tools))
  }

  if(!is.null(footer)){
    footer <- shiny::div(
      class = combine_class("card-footer", class_foot),
      footer
    )
  }

  set_attr_call(shiny::div(
    class = sprintf("card card-tabs %s", class),
    shiny::div(
      class = sprintf("card-header p-0 pt-1 %s", class_header),
      shiny::tags$ul(
        class = "nav nav-tabs",
        id = inputId,
        role = "tablist",
        title,
        lapply(seq_len(ntabs), function(ii) {
          title <- names[[ii]]
          card_tabset_header(inputId, ii, title, active = title %in% active)
        }),
        tools
      )
    ),
    shiny::div(
      class = combine_class("card-body", class_body),
      shiny::div(
        class = "tab-content",
        id = sprintf("%sContent", inputId),
        lapply(seq_len(ntabs), function(ii) {
          title <- names[[ii]]
          card_tabset_content(inputId, ii, active = title %in% active, tabs[[ii]])
        })
      )
    ),
    footer
  ), call = call_)
}

#' @export
card_tabset_insert <- function(inputId, title, ..., active = TRUE,
                            notify_on_failure = TRUE, session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage(
    "shinytemplates.card_tabset_insert",
    list(
      inputId = session$ns(inputId),
      title = title,
      body = as.character(shiny::tagList(...)),
      active = isTRUE(active),
      notify_on_failure = isTRUE(notify_on_failure)
    )
  )
}

#' @export
card_tabset_remove <- function(inputId, title, notify_on_failure = TRUE, session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage(
    "shinytemplates.card_tabset_remove",
    list(
      inputId = session$ns(inputId),
      title = title,
      notify_on_failure = isTRUE(notify_on_failure)
    )
  )
}

#' @export
card_tabset_activate <- function(inputId, title, notify_on_failure = TRUE, session = shiny::getDefaultReactiveDomain()){
  session$sendCustomMessage(
    "shinytemplates.card_tabset_activate",
    list(
      inputId = session$ns(inputId),
      title = title,
      notify_on_failure = isTRUE(notify_on_failure)
    )
  )
}
