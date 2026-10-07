#' @title Click a page element for an agent
#' @description Asks the browser to click the first element that matches
#' \code{selector}, for a tool call made by an agent (for example over
#' \code{MCP}). The browser does not click an element inside
#' \code{[mcp-agent-disabled="true"]}: such controls are for people only
#' (for example a button that overwrites files), and agents should ask the
#' user to click them. People's own clicks are not affected. Use this function
#' in tools instead of sending the \code{"shidashi.click"} message.
#' @param selector CSS selector of the element to click
#' @param session shiny session; for modules, the module session
#' @param timeout seconds to wait for the browser's answer
#' @returns A promise resolved with a list: \code{matched} (an element
#' matched the selector), \code{clicked}, \code{refused} (the element is
#' disabled for agents), and \code{note} (an invalid selector, for example).
#' The promise is rejected when the browser does not answer in time.
#' @examples
#'
#' # In a tool function (shiny session required):
#' # promises::then(mcp_click("#my_button", session), function(res) {
#' #   if (isTRUE(res$refused)) stop("The button is for people only")
#' #   "Clicked"
#' # })
#'
#' @export
mcp_click <- function(selector, session = shiny::getDefaultReactiveDomain(),
                      timeout = getOption("shidashi.click_timeout", 10)) {
  if (is.null(session)) {
    stop("`mcp_click` needs a shiny session.")
  }
  selector <- paste(selector, collapse = "")
  input_id <- "@shidashi_click_result@"

  # One registry and reply observer per (module) session
  key <- sprintf("shidashi_mcp_click@%s", session$ns(""))
  requests <- session$userData[[key]]
  if (is.null(requests)) {
    requests <- new_fastmap()
    session$userData[[key]] <- requests
    shiny::bindEvent(
      safe_observe({
        res <- as.list(session$input[[input_id]])
        rid <- res$request_id
        if (length(rid) != 1 || !requests$has(rid)) {
          return()
        }
        entry <- requests$get(rid)
        requests$remove(rid)
        entry$resolve(res)
      }, domain = session, priority = 101, label = "MCP click reply"),
      session$input[[input_id]],
      ignoreNULL = TRUE, ignoreInit = FALSE
    )
  }

  request_id <- rand_string()
  promise <- promises::promise(function(resolve, reject) {
    requests$set(request_id, list(resolve = resolve, reject = reject))
  })

  # Errors in `later` callbacks would surface in the event loop
  later::later(function() {
    tryCatch({
      if (!requests$has(request_id)) {
        return()
      }
      entry <- requests$get(request_id)
      requests$remove(request_id)
      entry$reject(simpleError(sprintf(paste(
        "The browser did not answer within %s s: the module page may not",
        "be open."
      ), format(timeout))))
    }, error = function(e) {
      warning("[shidashi] click timeout failed: ", conditionMessage(e),
              call. = FALSE)
    })
  }, delay = timeout)

  # Same short pause as `shiny_query_ui`: a change sent at about the same
  # time (e.g. an input the click depends on) reaches the page first
  later::later(function() {
    tryCatch({
      if (!requests$has(request_id)) {
        return()
      }
      session$sendCustomMessage("shidashi.click", list(
        selector = selector,
        agent = TRUE,
        request_id = request_id,
        input_id = session$ns(input_id)
      ))
    }, error = function(e) {
      warning("[shidashi] click request failed: ", conditionMessage(e),
              call. = FALSE)
    })
  }, delay = getOption("shidashi.query_ui_delay", 0.1))

  promise
}
