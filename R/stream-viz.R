#' Output placeholder for a streaming visualization widget
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

#' Render a streaming widget
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

#' Create a streaming widget
#'
#' Creates a multi-channel signal viewer widget that fetches its data from
#' the binary stream file produced by \code{\link{stream_to_js}}.
#'
#' The \code{outputId} together with \code{session} is used to auto-compute
#' the token-qualified stream file identifier via
#' \code{\link{stream_file_id}}.  You can override this by passing an
#' explicit \code{stream_id}.
#'
#' Use \code{\link{updateStreamViz}} for in-place updates without recreating
#' the widget.
#'
#' @param outputId Character scalar.  The output ID matching the
#'   corresponding \code{\link{streamVizOutput}} call.  Used to compute
#'   \code{stream_id} automatically when \code{stream_id} is \code{NULL}.
#' @param session Shiny session object.  Defaults to the active reactive
#'   domain.  Together with \code{outputId} determines the token-qualified
#'   stream file identifier.
#' @param stream_id Character scalar or \code{NULL}.  When \code{NULL}
#'   (default) the stream identifier is computed as
#'   \code{stream_file_id(outputId, session, token = token)}.  Provide an
#'   explicit value to override for non-Shiny or advanced use.
#' @param width,height Widget dimensions (passed to \code{\link[htmlwidgets]{createWidget}}).
#' @param refresh_rate Numeric scalar (milliseconds). Polling interval used
#'   when the viewer is in \emph{active streaming} mode (play button pressed).
#'   Lower values give smoother animation but increase CPU/network load.
#'   Default \code{33} (approximately 30 Hz).
#' @param show_controls Logical. Whether to display the hover toolbar
#'   (play/pause, zoom, reset, export).  Default \code{TRUE}.
#' @param streaming Logical.  Whether to start active streaming immediately
#'   when the widget is rendered.  Default \code{FALSE}; set to \code{TRUE}
#'   to begin polling for new data automatically.  Can also be toggled later
#'   via \code{\link{updateStreamViz}}.
#' @param token Character scalar or \code{NULL}.  When \code{NULL} (default)
#'   the session's own token is used.  Override with a parent session token
#'   when running inside a standalone viewer (pop-out window) so that the
#'   child session fetches the parent's binary stream file.
#' @return An \pkg{htmlwidgets} object.
#' @seealso \code{\link{streamVizOutput}}, \code{\link{renderStreamViz}},
#'   \code{\link{updateStreamViz}}, \code{\link{stream_file_id}}
#' @export
stream_viz <- function(outputId, session = shiny::getDefaultReactiveDomain(),
                       stream_id = NULL, width = NULL, height = NULL,
                       refresh_rate = 33, show_controls = TRUE,
                       streaming = FALSE, token = NULL) {
  if (is.null(stream_id)) {
    stream_id <- stream_file_id(outputId, session, token = token)
  }
  htmlwidgets::createWidget(
    name = "stream_viz",
    x = list(
      stream_id = stream_id,
      refresh_rate = refresh_rate,
      show_controls = show_controls,
      streaming = isTRUE(streaming)
    ),
    width = width,
    height = height,
    package = "shidashi"
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
#' @param token Character scalar or \code{NULL}.  When \code{NULL} (default)
#'   the session's own token is used.  Override with a parent session token
#'   so that a standalone viewer (child session) can address the parent's
#'   binary stream file.
#' @return Character scalar: \code{"{token}_{id}"}.
#' @seealso \code{\link{stream_path}}, \code{\link{stream_viz}},
#'   \code{\link{updateStreamViz}}
#' @export
stream_file_id <- function(id, session = shiny::getDefaultReactiveDomain(),
                           token = NULL) {
  if (is.null(token)) {
    token <- if (!is.null(session)) session$token else "static"
  }
  nsid <- if (!is.null(session)) session$ns(id) else id
  paste0(token, "_", nsid)
}

#' Trigger an in-place update of a streaming widget
#'
#' Sends a custom Shiny message that causes the browser to re-fetch the binary
#' stream file and re-render the signal viewer without tearing down and
#' recreating the widget.  Call this after writing new data with
#' \code{\link{stream_to_js}}.  The \code{outputId} is used both
#' to locate the widget as the stream file identifier — it must
#' match the \code{id} passed to \code{\link{stream_path}}.
#'
#' @param session Shiny session object. Defaults to the active reactive domain.
#' @param outputId Character scalar. The output ID passed to
#'   \code{\link{streamVizOutput}} (and to \code{\link{stream_path}}).
#' @param streaming Logical or \code{NULL}.  \code{TRUE} starts active
#'   streaming (the widget polls for new data via \code{requestAnimationFrame});
#'   \code{FALSE} pauses it; \code{NULL} (default) leaves the current
#'   streaming state unchanged.
#' @param token Character scalar or \code{NULL}.  When \code{NULL} (default)
#'   the session's own token is used.  Override with a parent session token
#'   when running inside a standalone viewer (pop-out window) so that the
#'   child session fetches the parent's binary stream file.
#' @return Invisibly \code{NULL}.
#' @seealso \code{\link{streamVizOutput}}, \code{\link{stream_to_js}},
#'   \code{\link{stream_file_id}}
#' @export
updateStreamViz <- function(outputId, streaming = NULL, token = NULL,
                            session = shiny::getDefaultReactiveDomain()) {
  msg <- list(
    id = session$ns(outputId),
    stream_id = stream_file_id(outputId, session, token = token)
  )
  if (is.logical(streaming) && length(streaming) == 1L && !is.na(streaming)) {
    msg$streaming <- streaming
  }
  session$sendCustomMessage("stream_viz.render", msg)
}
