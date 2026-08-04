colormap_swatch_html <- function(colors, continuous, height = "10px") {

  colors <- grDevices::rgb(t(grDevices::col2rgb(colors)), maxColorValue = 255)
  n <- length(colors)
  if (!n) { return("") }

  frame <- paste0(
    "display:block;width:100%;height:", height, ";",
    "border:1px solid rgba(128,128,128,.4);border-radius:2px;",
    "overflow:hidden;font-size:0;line-height:0;"
  )

  if (continuous) {
    stops <- if (n == 1) {
      colors
    } else {
      sprintf("%s %.2f%%", colors, seq(0, 100, length.out = n))
    }
    return(sprintf(
      '<span style="%sbackground:linear-gradient(to right,%s);"></span>',
      frame, paste(stops, collapse = ",")
    ))
  }

  blocks <- sprintf(
    '<span style="display:inline-block;height:100%%;width:%.4f%%;background:%s;"></span>',
    100 / n, colors
  )
  sprintf('<span style="%s">%s</span>', frame, paste0(blocks, collapse = ""))
}



#' @title A shiny color picker
#' @description
#' Displays color right by the color names for better user experience;
#' implemented using vanilla shiny selector
#' @param colormaps A named list with name being the color-map names and values
#' being a character vector of key colors
#' @param inputId,label,selected passed to shiny
#' \code{\link[shiny]{selectInput}}; \code{selected} must be one of the
#' names of color map list
#' @param continuous whether the color map is continuous; default is false
#' @returns A shiny selector
#' @examples
#'
#'
#'
#' colormaps <- list(
#'   Dark2 = c("#1b9e77", "#d95f02", "#7570b3", "#e7298a",
#'             "#66a61e", "#e6ab02", "#a6761d", "#666666"),
#'   Paired = c("#a6cee3", "#1f78b4", "#b2df8a", "#33a02c",
#'              "#fb9a99", "#e31a1c", "#fdbf6f", "#ff7f00"),
#'   Pastel1 = c("#fbb4ae", "#b3cde3", "#ccebc5", "#decbe4",
#'               "#fed9a6", "#ffffcc", "#e5d8bd", "#fddaec"),
#'   Set1 = c("#e41a1c", "#377eb8", "#4daf4a", "#984ea3",
#'            "#ff7f00", "#ffff33", "#a65628", "#f781bf")
#' )
#'
#' color_picker <- colormapSelectInput(
#'   inputId = "colormap", label = "Pick a colormap",
#'   colormaps = colormaps, continuous = FALSE
#' )
#'
#' if (interactive()) {
#'   shiny::shinyApp(
#'     ui = color_picker,
#'     server = function(input, output, server) {
#'       shiny::observe({
#'         print(colormaps[[input$colormap]])
#'       })
#'     }
#'   )
#' }
#'
#'
#' @export
colormapSelectInput <- function(inputId, label, colormaps, selected = NULL,
                                  continuous = FALSE) {

  bars <- vapply(colormaps, colormap_swatch_html, character(1L),
                 continuous = continuous, USE.NAMES = TRUE)
  bars_json <- jsonlite::toJSON(as.list(bars), auto_unbox = TRUE)

  render <- sprintf(
    "{
  option: function(item, escape) {
    var bars = %s;
    return '<div class=\"option\" style=\"padding:4px 8px;\">' +
      '<div style=\"line-height:1.4;\">' + escape(item.label) + '</div>' +
      (bars[item.value] || '') + '</div>';
  },
  item: function(item, escape) {
    var bars = %s;
    return '<div class=\"item\">' + escape(item.label) +
      '<span style=\"display:inline-block;width:70px;margin-left:6px;' +
      'vertical-align:middle;\">' + (bars[item.value] || '') + '</span></div>';
  }
}",
    bars_json, bars_json
  )

  shiny::selectizeInput(
    inputId = inputId,
    label = label,
    choices = names(colormaps),
    selected = selected,
    options = list(render = I(render))
  )
}
