# ---- Standalone viewer for popped-out outputs ----

#' @title Server function for the standalone viewer module
#' @description Internal server function used by the \code{standalone_viewer}
#'   hidden module. Retrieves the render function from the parent module session
#'   and assigns it to the viewer's output.
#' @param input,output,session Shiny module server arguments
#' @param ... ignored
#' @keywords internal
#' @export
server_standalone_viewer <- function(input, output, session, ...) {

  # The viewer's root scope (same root as all modules in this app)
  root_session <- session$rootScope()

  # Parse query parameters from the URL
  query <- shiny::parseQueryString(
    shiny::isolate(session$clientData$url_search)
  )
  url_output_id <- query$outputId  # namespaced, e.g. "demo-iris_plot"
  url_token     <- query$token     # root session token

  if (!length(url_output_id) || !nzchar(url_output_id) ||
      !length(url_token)     || !nzchar(url_token)) {
    output$viewer_content <- shiny::renderUI({
      shiny::h3("Missing outputId or token in URL.")
    })
    return(invisible())
  }

  # Look up the parent session's entry by token
  entry <- get_session_entry(url_token)
  if (is.null(entry)) {
    output$viewer_content <- shiny::renderUI({
      shiny::h3("Session not found. The parent session may have closed.")
    })
    return(invisible())
  }

  # entry$shiny_session is the module's session proxy (namespaced)
  module_session <- entry$shiny_session
  module_id <- module_session$ns(NULL)

  # Get the root scope of the module session
  module_root <- module_session$rootScope()

  # Build the namespaced output ID
  ns2 <- shiny::NS(module_id)

  # The URL's outputId is already namespaced (e.g. "demo-iris_plot").
  # Strip the namespace prefix to get the bare outputId
  bare_id <- url_output_id
  ns_prefix <- paste0(module_id, "-")
  if (nzchar(module_id) && startsWith(url_output_id, ns_prefix)) {
    bare_id <- substring(url_output_id, nchar(ns_prefix) + 1L)
  }

  full_outputId <- ns2(bare_id)

  # Retrieve the render function already assigned to the output
  render_function <- module_root$getOutput(full_outputId)

  if (!is.function(render_function)) {
    output$viewer_content <- shiny::renderUI({
      shiny::h3(sprintf(
        "Cannot find render function for output: %s", bare_id
      ))
    })
    return(invisible())
  }

  # Get the output UI function (e.g. plotOutput, verbatimTextOutput)
  ui_function <- attr(render_function, "outputFunc")

  # Get output options from the stored renderers
  output_opts <- list()
  renderer <- NULL
  if (!is.null(entry$output_renderers)) {
    renderer <- entry$output_renderers$get(bare_id)
    if (is.list(renderer)) {
      output_opts <- renderer$output_opts
    }
  }

  local_data <- fastmap::fastmap()

  # Use the module's reactive domain so reactive expressions in the
  # render function can access module inputs/reactives
  shiny::withReactiveDomain(module_root, {

    # Assign the wrapper UI to the viewer module's output (namespaced)
    output$viewer_content <- shiny::renderUI({
      output_args <- c(list(full_outputId), as.list(output_opts))
      output_args_fullvp <- output_args
      output_args_fullvp$width <- "100vw"
      output_args_fullvp$height <- "100vh"

      tryCatch(
        do.call(ui_function, output_args_fullvp),
        error = function(e) {
          do.call(ui_function, output_args)
        }
      )
    })

    # Assign the original render function at root scope
    # (matches the namespaced ID embedded in the UI element)
    root_session$output[[full_outputId]] <- render_function

    # stream_viz outputs are handled automatically: the render expression
    # captures session from its lexical scope, so stream_file_id() computes
    # the correct token-qualified path to the parent's binary file.  The
    # streaming flag in the widget's x list triggers startStreaming() in
    # renderValue on the JS side — no custom message needed.

  })

  # Forward inputs from viewer to the parent module's session.
  # Use the standalone viewer's own domain so the observer fires
  # in the same flush cycle as the input update (avoids cross-session
  # timing issues with event-type inputs).
  shiny::observe({
    inputs <- shiny::reactiveValuesToList(root_session$input)
    nms <- names(inputs)
    nms <- nms[startsWith(nms, ns2("")) & !startsWith(nms, "@")]
    if (!length(nms)) {
      return()
    }
    for (nm in nms) {
      sig <- digest::digest(inputs[[nm]])
      if (!identical(sig, local_data$get(nm))) {
        module_root$sendCustomMessage(
          "shidashi.set_shiny_input",
          list(
            inputId = nm,
            value = inputs[[nm]],
            priority = "event"
          )
        )
        local_data$set(nm, sig)
      }
    }
  }, domain = root_session, autoDestroy = TRUE)

  invisible()
}
