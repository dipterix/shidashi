#' Output placeholder for a stream\_viz widget
#'
#' Use in a Shiny UI to reserve a slot for a multi-channel signal viewer
#' that is driven by binary stream data.
#'
#' @param outputId Character scalar. Output ID that matches the corresponding
#'   \code{\link{renderStreamViz}} call.
#' @param width,height CSS width and height of the widget container.
#' @return An HTML output element suitable for inclusion in a Shiny UI.
#' @seealso \code{\link{renderStreamViz}}, \code{\link{updateStreamViz}}
#' @export
streamVizOutput <- function(outputId, width = "100%", height = "400px") {
  htmlwidgets::shinyWidgetOutput(
    outputId, "stream_viz",
    width = width, height = height,
    package = "shidashi"
  )
}

#' Render a stream\_viz widget
#'
#' Server-side render function for \code{\link{streamVizOutput}}.
#' The expression should evaluate to a \code{\link{stream_viz}} object.
#'
#' @param expr An R expression that returns a \code{\link{stream_viz}} widget.
#' @param env Environment in which to evaluate \code{expr}.
#' @param quoted Logical. Whether \code{expr} is already quoted.
#' @return A server-side render function for use with Shiny.
#' @seealso \code{\link{streamVizOutput}}, \code{\link{updateStreamViz}}
#' @export
renderStreamViz <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  htmlwidgets::shinyRenderWidget(expr, streamVizOutput, env, quoted = TRUE)
}

#' Create a stream\_viz widget
#'
#' Creates a multi-channel signal viewer widget that fetches its data from
#' the binary stream file produced by \code{\link{stream_to_js}}.
#'
#' The \code{stream_id} argument must be the full token-qualified identifier
#' returned by \code{\link{stream_file_id}}: \code{paste0(session$token, "_", id)}.
#' Use \code{\link{updateStreamViz}} for in-place updates without recreating the
#' widget.
#'
#' @param stream_id Character scalar. The stream file identifier including the
#'   session token prefix, e.g. \code{paste0(session$token, "_mydata")}.
#'   \code{NULL} renders an empty placeholder.
#' @param width,height Widget dimensions (passed to htmlwidgets).
#' @param elementId Optional explicit HTML element ID.
#' @return An htmlwidget object.
#' @seealso \code{\link{streamVizOutput}}, \code{\link{renderStreamViz}},
#'   \code{\link{updateStreamViz}}, \code{\link{stream_file_id}}
#' @export
stream_viz <- function(stream_id = NULL, width = NULL, height = NULL,
                       elementId = NULL) {
  htmlwidgets::createWidget(
    name = "stream_viz",
    x = list(stream_id = stream_id),
    width = width,
    height = height,
    package = "shidashi",
    elementId = elementId
  )
}

#' Build the token-qualified stream file identifier
#'
#' Combines \code{session$token} with \code{id} to produce the string used
#' both by \code{\link{stream_path}} (as the filename stem) and by the browser
#' as the URL path component under \code{stream/}.
#'
#' @param id Character scalar. The base stream identifier (no path separators).
#' @param session Shiny session object. Defaults to the active reactive domain.
#' @return Character scalar: \code{"{token}_{id}"}.
#' @seealso \code{\link{stream_path}}, \code{\link{stream_viz}},
#'   \code{\link{updateStreamViz}}
#' @export
stream_file_id <- function(id, session = shiny::getDefaultReactiveDomain()) {
  token <- if (!is.null(session)) session$token else "static"
  paste0(token, "_", session$ns(id))
}

#' Trigger an in-place update of a stream\_viz widget
#'
#' Sends a custom Shiny message that causes the browser to re-fetch the binary
#' stream file and re-render the signal viewer without tearing down and
#' recreating the widget.  Call this after writing new data with
#' \code{\link{stream_to_js}}.  The \code{outputId} is used both
#' to locate the widget in the DOM and as the stream file identifier — it must
#' match the \code{id} passed to \code{\link{stream_path}}.
#'
#' @param session Shiny session object. Defaults to the active reactive domain.
#' @param outputId Character scalar. The output ID passed to
#'   \code{\link{streamVizOutput}} (and to \code{\link{stream_path}}).
#' @return Invisibly \code{NULL}.
#' @seealso \code{\link{streamVizOutput}}, \code{\link{stream_to_js}},
#'   \code{\link{stream_file_id}}
#' @export
updateStreamViz <- function(session = shiny::getDefaultReactiveDomain(),
                            outputId) {
  session$sendCustomMessage(
    "stream_viz.render",
    list(id = session$ns(outputId), stream_id = stream_file_id(outputId, session))
  )
}
