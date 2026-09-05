jqueryui_dependency <- function() {
  path <- system.file("www/shared/jqueryui", package = "shiny")
  if (!dir.exists(path)) { return(NULL) }

  version <- tryCatch({
    v <- get0("version_jqueryui", envir = asNamespace("shiny"),
              inherits = FALSE, ifnotfound = NULL)
    if (is.character(v) && length(v) == 1L) { v } else { "1.14.1" }
  }, error = function(e) { "1.14.1" })

  htmltools::htmlDependency(
    name = "jqueryui",
    version = version,
    src = "www/shared/jqueryui",
    package = "shiny",
    script = "jquery-ui.min.js"
  )
}

# Layout only: no colors, so the shipped 'selectize' theme (and dark-mode
# overrides from the dashboard template) keep applying.
object_list_style <- local({
  style <- NULL

  function() {
    if (is.null(style)) {
      style <<- shiny::tags$style(shiny::HTML(
        ".shidashi-object-list .selectize-input { display: block; }
.shidashi-object-list .selectize-control.multi .selectize-input > div.item {
  display: flex; align-items: center; width: 100%;
  margin: 2px 0; box-sizing: border-box;
}
.shidashi-object-list .selectize-input > div.item > .object-list-label {
  flex: 1 1 auto; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
/* `shiny.min.css` hides the remove anchor unless it is the first element
   child of the row; the label comes first here, so it must be re-shown */
.shidashi-object-list .selectize-input > div.item > a.remove {
  display: inline-block !important; flex: 0 0 auto;
}
/* `list-only`: entries come from the server, so the dropdown and the text
   field it belongs to are collapsed away */
.shidashi-object-list.list-only .selectize-dropdown { display: none !important; }
.shidashi-object-list.list-only .selectize-input > input {
  position: absolute !important; opacity: 0 !important; width: 0px; height: 0px;
}
/* a collapsed text field cannot show selectize's own placeholder, so the
   empty state is drawn from a custom property set on the container instead */
.shidashi-object-list.list-only .selectize-input:not(.has-items)::after {
  content: var(--object-list-placeholder, \"\");
  display: block; opacity: 0.6;
}"
      ))
    }
    htmltools::singleton(style)
  }
})

# Quotes a string so it can be used as a CSS `content` value
css_string <- function(x) {
  x <- gsub("[\r\n]+", " ", x)
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("'", "\\'", x, fixed = TRUE)
  sprintf("'%s'", x)
}

# Normalizes `choices` to a named list; names are the displayed labels and
# values are the item keys. Unnamed entries use their value as the label.
object_list_choices <- function(choices) {
  if (!length(choices)) { return(list()) }
  choices <- as.list(choices)
  labels <- names(choices)
  if (is.null(labels)) { labels <- rep("", length(choices)) }
  blank <- is.na(labels) | !nzchar(labels)
  if (any(blank)) {
    labels[blank] <- vapply(choices[blank], function(x) {
      paste(as.character(x), collapse = "")
    }, character(1L))
  }
  names(choices) <- labels
  choices
}

object_list_render <- paste0(
  "{\n",
  "  item: function(item, escape) {\n",
  "    return '<div class=\"item\" title=\"' + escape(item.label) + '\">' +\n",
  "      '<span class=\"object-list-label\">' + escape(item.label) +\n",
  "      '</span></div>';\n",
  "  }\n",
  "}"
)

# `drag_drop` attaches jQuery UI `sortable` to the whole control, so a click on
# the remove anchor can be swallowed by a drag start; excluding it restores the
# click. The plugin wraps `setup()` and attaches `sortable` *after* the wrapped
# call, which is what fires `initialize`, so the option has to be set on the
# next tick rather than inline.
object_list_oninit <- paste0(
  "function() {\n",
  "  var self = this;\n",
  "  setTimeout(function() {\n",
  "    try { self.$control.sortable('option', 'cancel', 'a.remove'); }\n",
  "    catch (e) {}\n",
  "  }, 0);\n",
  "}"
)

#' @title A re-orderable list of objects as a shiny input
#' @description
#' Displays the selected objects as a vertical list; entries can be dragged to
#' re-order and removed with the \verb{X} button on the right. The value is a
#' character vector of the entry keys, in the order shown on screen.
#' Implemented using vanilla shiny \code{\link[shiny]{selectizeInput}}, hence
#' no additional 'JavaScript' library is needed.
#' @param inputId,label,width passed to \code{\link[shiny]{selectizeInput}}
#' @param choices a named list or character vector of the entries; the names are
#' the text displayed in each row and the values are the entry keys returned by
#' the input; the order of \code{choices} is the order of the rows
#' @param selected keys of the entries to show; default is all of
#' \code{choices}
#' @param placeholder text to display when the list is empty
#' @param allow_readd whether the entries can be selected again from a
#' drop-down menu; when \code{FALSE} the list only shows what the
#' server puts in it, and removing an entry is final until it is added again
#' from the server; when \code{TRUE} a removed entry stays available in the
#' menu and re-selecting it appends it to the end of the list; default is
#' \code{TRUE}
#' @param sortable whether the entries can be dragged to re-order; requires
#' 'jQuery' 'UI' shipped with \pkg{shiny}, and is silently disabled when
#' unavailable
#' @param removable whether each entry has a button to remove itself
#' @param session shiny session
#' @returns \code{objectListInput} returns a shiny input; the input value is a
#' character vector of the entry keys in display order.
#' \code{updateObjectListInput} is called for its side effect.
#'
#' @examples
#'
#'
#' ui <- shiny::basicPage(
#'   objectListInput(
#'     inputId = "objects", label = "Selected objects",
#'     choices = character(),
#'     selected = character()
#'   ),
#'   shiny::actionButton("btn", "Add")
#' )
#'
#' if (interactive()) {
#'   shiny::shinyApp(
#'     ui = shiny::fluidPage(ui, shiny::verbatimTextOutput("selected")),
#'     server = function(input, output, session) {
#'       output$selected <- shiny::renderPrint({ input$objects })
#'
#'       shiny::bindEvent(
#'         shiny::observe({
#'           shidashi::updateObjectListInput(
#'             inputId = "objects",
#'             choices = c(
#'               "Electrode 1 [LA1]" = "elec_1",
#'               "Streamlines [n=12]" = "streamlines_1",
#'               "Overlay aparc [discrete]" = "volume_1"
#'             )
#'           )
#'         }),
#'         input$btn
#'       )
#'     }
#'   )
#' }
#'
#'
#' @export
objectListInput <- function(inputId, label = NULL, choices = NULL,
                            selected = NULL, width = NULL,
                            placeholder = "(No object selected)",
                            sortable = TRUE, removable = TRUE,
                            allow_readd = TRUE) {

  choices <- object_list_choices(choices)
  if (is.null(selected)) {
    selected <- unname(unlist(choices))
  }
  allow_readd <- isTRUE(allow_readd)
  has_placeholder <- length(placeholder) == 1L && !is.na(placeholder) &&
    nzchar(placeholder)

  dependency <- NULL
  sortable <- isTRUE(sortable)
  if (sortable) {
    dependency <- jqueryui_dependency()
    # `drag_drop` throws when jQuery UI `sortable` is missing, taking the whole
    # page down with it; degrade to a non-sortable list instead
    sortable <- !is.null(dependency)
  }

  plugins <- c("remove_button"[isTRUE(removable)], "drag_drop"[sortable])

  options <- list(
    render = I(object_list_render),
    openOnFocus = allow_readd,
    create = FALSE,
    # keeps a removed entry available in the dropdown so it can be re-added
    persist = TRUE
  )
  if (length(plugins)) {
    options$plugins <- as.list(plugins)
  }
  if (sortable) {
    options$onInitialize <- I(object_list_oninit)
  }

  container_class <- "shidashi-object-list"
  container_style <- NULL

  if (allow_readd) {
    # the text field is visible, so selectize draws the placeholder itself
    if (has_placeholder) { options$placeholder <- placeholder }
    # a re-selected entry joins the list at the end rather than at the caret
    options$onDropdownOpen <- I("function() { this.setCaret(this.items.length); }")
  } else {
    container_class <- paste(container_class, "list-only")
    if (has_placeholder) {
      container_style <- sprintf("--object-list-placeholder:%s;",
                                 css_string(placeholder))
    }
  }

  shiny::tagList(
    dependency,
    object_list_style(),
    shiny::div(
      class = container_class,
      style = container_style,
      shiny::selectizeInput(
        inputId = inputId,
        label = label,
        choices = choices,
        selected = selected,
        multiple = TRUE,
        width = width,
        options = options
      )
    )
  )
}

#' @rdname objectListInput
#' @export
updateObjectListInput <- function(session = shiny::getDefaultReactiveDomain(),
                                  inputId, label = NULL, choices = NULL,
                                  selected = choices) {
  # The client rebuilds the widget from the `<option>` elements, so the row
  # order comes from `choices`, not from `selected`
  choices <- object_list_choices(choices)
  if (is.null(selected)) {
    selected <- unname(unlist(choices))
  }
  shiny::updateSelectizeInput(
    session = session,
    inputId = inputId,
    label = label,
    choices = choices,
    selected = selected,
    server = FALSE
  )
}
