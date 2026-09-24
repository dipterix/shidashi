# ---- ask_user: ask the human a question (browser modal or R console) ----
#
# Used by the in-dashboard chat (the `ask_user` tool) and by the permission
# wrapper to confirm destructive tool calls (see `wrap_tools_with_permissions`).

#' Ask the user a question
#'
#' Tries three strategies in order:
#' \enumerate{
#'   \item If a live Shiny session is provided, ask via a browser modal.
#'   \item If \code{interactive()}, ask via the R console.
#'   \item Otherwise reject with an error.
#' }
#' @param arguments list with \code{message}, optional \code{choices},
#'   optional \code{allow_freeform}.
#' @param shiny_session A Shiny session or \code{NULL}.
#' @return A \code{promises::promise} (Shiny path) or a plain list with
#'   \code{content} and \code{isError}.
#' @keywords internal
#' @noRd
mcp_tool_ask_user <- function(arguments, shiny_session = NULL) {

  message_text <- arguments$message
  if (!is.character(message_text) || !nzchar(message_text)) {
    return(list(
      content = list(list(
        type = "text",
        text = "Invalid params: 'message' is required."
      )),
      isError = TRUE
    ))
  }

  choices <- as.character(unlist(arguments$choices))
  allow_freeform <- !identical(arguments$allow_freeform, FALSE)

  # --- Strategy 1: Shiny browser modal -----------------------------------
  session_ok <- !is.null(shiny_session) &&
    is.environment(shiny_session) &&
    !isTRUE(tryCatch(shiny_session$isClosed(), error = function(e) TRUE))

  if (session_ok) {
    return(mcp_tool_ask_user_shiny(
      message_text, choices, allow_freeform, shiny_session,
      tool_name = arguments$tool_name,
      intent = arguments$intent
    ))
  }

  # --- Strategy 2: interactive R console ---------------------------------
  if (interactive()) {
    return(mcp_tool_ask_user_console(
      message_text, choices, allow_freeform
    ))
  }

  # --- Strategy 3: reject ------------------------------------------------
  list(
    content = list(list(
      type = "text",
      text = "Cannot ask user: no Shiny session available and R is not interactive."
    )),
    isError = TRUE
  )
}

# Ask user via Shiny browser modal (returns a promise)
mcp_tool_ask_user_shiny <- function(message_text, choices, allow_freeform,
                                    shiny_session,
                                    tool_name = NULL, intent = NULL) {
  request_id <- rand_string(prefix = "ask_user_")
  input_id <- shiny_session$ns("@shidashi_ask_user_result@")

  payload <- list(
    request_id = request_id,
    input_id = input_id,
    message = message_text,
    choices = choices,
    allow_freeform = allow_freeform
  )
  if (length(tool_name) == 1 && nzchar(tool_name)) {
    payload$tool_name <- tool_name
  }
  if (length(intent) == 1 && nzchar(intent)) {
    payload$intent <- intent
  }
  shiny_session$sendCustomMessage("shidashi.ask_user", payload)

  check_fn <- coro::async(function() {
    remaining <- 120L  # 120 x 500ms = 60 seconds timeout

    while (remaining >= 0) {
      remaining <- remaining - 1L
      res <- shiny::isolate(
        shiny_session$input[["@shidashi_ask_user_result@"]]
      )
      if (!is.null(res) && identical(res$request_id, request_id)) {
        if (isTRUE(res$cancelled)) {
          return(list(
            content = list(list(type = "text",
                                text = "User cancelled the request.")),
            isError = FALSE
          ))
        } else {
          return(list(
            content = list(list(type = "text",
                                text = res$value %||% "")),
            isError = FALSE
          ))
        }
      } else {
        coro::async_sleep(0.5)
      }
    }

    return(list(
      content = list(list(type = "text",
                          text = "Timeout: no response from user within 60 seconds.")),
      isError = FALSE
    ))

  })
  check_fn()
}

# Ask user via the R console (synchronous, returns a plain list)
mcp_tool_ask_user_console <- function(message_text, choices, allow_freeform) {
  cat("\n", message_text, "\n", sep = "")
  answer <- NULL

  if (length(choices)) {
    sel <- utils::menu(choices, title = "Select an option:")
    if (sel == 0L) {
      return(list(
        content = list(list(type = "text",
                           text = "User cancelled the request.")),
        isError = FALSE
      ))
    }
    answer <- choices[[sel]]
  }

  if (allow_freeform) {
    prompt <- if (is.null(answer)) "Your response: " else "Additional input (or Enter to skip): "
    freeform <- readline(prompt)
    if (nzchar(freeform)) {
      answer <- if (is.null(answer)) freeform else paste0(answer, "\n", freeform)
    }
  }

  if (is.null(answer) || !nzchar(answer)) {
    answer <- "(no response)"
  }

  list(
    content = list(list(type = "text", text = answer)),
    isError = FALSE
  )
}
