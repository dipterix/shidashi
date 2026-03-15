# Format a cost value with appropriate decimal places
format_cost <- function(cost) {
  if (is.na(cost) || is.null(cost)) return("$?")
  if (cost < 0.01) {
    sprintf("$%.4f", cost)
  } else if (cost < 0.10) {
    sprintf("$%.3f", cost)
  } else {
    sprintf("$%.2f", cost)
  }
}

format_token <- function(cost) {
  if (is.na(cost) || is.null(cost)) return("0")
  # 1G = 1000M = 1e6K = 1e9
  base <- 1
  unit <- ""
  if (cost >= 1e10) {
    base <- 1e9
    unit <- "G"
  } else if (cost >= 1e7) {
    base <- 1e6
    unit <- "M"
  } else if (cost >= 1e4) {
    base <- 1e3
    unit <- "K"
  }
  sprintf("%s%s", format(cost / base, big.mark = ",", digits = 4), unit)
}

#' Chat-bot UI panel
#'
#' @description
#' Returns the UI elements for the AI chat panel: a header bar with
#' a \dQuote{New conversation} button and the \pkg{shinychat} widget.
#'
#' When \pkg{shinychat} is not installed or the chat-bot is disabled via
#' \code{options(shidashi.chatbot = FALSE)}, returns an empty
#' \code{tagList()}.
#'
#' Typically called inside \code{shiny::renderUI} by
#' \code{\link{chatbot_server}()} to fill a \code{\link{module_drawer}}.
#' Can also be placed anywhere in module UI directly.
#'
#' @param id character; the Shiny input/output namespace for the chat
#'   widget. Default \code{"shidashi-chatbot"}.
#' @return A \code{shiny::tagList} containing the chat UI or empty.
#' @keywords internal
chatbot_ui <- function(id, modes = NULL, default_mode = NULL) {
  if (!isTRUE(getOption("shidashi.chatbot", TRUE))) {
    return(shiny::tagList("AI is disabled"))
  }
  if (!requireNamespace("shinychat", quietly = TRUE)) {
    return(shiny::tagList(
      "Package `shinychat` must be installed to enable this feature"
    ))
  }
  conv_select_id <- paste0(id, "-conv_select")
  new_conv_id    <- paste0(id, "-new_conversation")
  mode_select_id <- paste0(id, "-mode_select")
  confirm_policy_id <- paste0(id, "-confirm_policy")
  status_id      <- paste0(id, "-status")

  # Build mode selector if modes are defined
  mode_ui <- NULL
  if (length(modes)) {
    # Use mode names only (no descriptions)
    mode_choices <- vapply(modes, function(m) m$name, character(1))
    names(mode_choices) <- vapply(modes, function(m) {
      sprintf("%s - %s", m$name, m$description %||% "")
    }, character(1))
    selected <- if (length(default_mode)) default_mode else mode_choices[[1]]
    mode_ui <- shiny::selectInput(
      mode_select_id,
      label = NULL,
      choices = mode_choices,
      selected = selected,
      width = "100%"
    )
  }

  # Confirmation policy selector
  confirm_policy_ui <- shiny::selectInput(
    confirm_policy_id,
    label = NULL,
    choices = c(
      "Auto-allow" = "auto_allow",
      "Ask before changes" = "ask",
      "Auto-reject" = "auto_reject"
    ),
    selected = "auto_allow",
    width = "100%"
  )

  # Conversation selector
  conv_ui <- shiny::div(
    class = "shidashi-chatbot-conv-select flex-grow-1",
    shiny::selectInput(
      conv_select_id,
      label = NULL,
      choices = c("New conversation" = "1"),
      width = "100%"
    )
  )

  # New conversation button
  new_conv_ui <- shiny::actionLink(
    new_conv_id, label = NULL,
    icon = shiny::icon("plus"),
    title = "New conversation",
    class = "shidashi-chatbot-new-conv shidashi-chatbot-ops-btn btn btn-sm btn-outline-secondary"
  )

  # Copy conversation button (plain button triggers JS directly)
  copy_conv_ui <- shiny::tags$button(
    type = "button",
    class = "shidashi-chatbot-copy-conv shidashi-chatbot-ops-btn btn btn-sm btn-outline-secondary",
    title = "Copy conversation to clipboard",
    `data-shidashi-action` = "copy-conversation",
    `data-shidashi-chat-id` = id,
    shiny::icon("copy")
  )

  shiny::tagList(
    # Chat UI - stop button will be injected dynamically via JS
    shinychat::chat_ui(id, fill = TRUE),
    # Control bar: all selectors in one compact row (dropup)
    shiny::div(
      class = "shidashi-chatbot-controls d-flex align-items-center gap-1 px-1 py-1",
      shiny::div(
        style = "flex: 3;",
        mode_ui
      ),
      shiny::div(
        style = "flex: 3;",
        confirm_policy_ui
      ),
      shiny::div(
        style = "flex: 5;",
        conv_ui
      ),
      shiny::div(
        class = "d-flex gap-1",
        new_conv_ui,
        copy_conv_ui
      )
    ),
    # Status bar: model name, token counts, estimated cost
    shiny::tags$footer(
      id = status_id,
      class = "shidashi-chatbot-status d-flex align-items-center gap-2 small font-monospace px-2 py-1",
      shiny::span(
        id = paste0(status_id, "-model"),
        class = "shidashi-chatbot-status-model text-truncate"
      ),
      shiny::span(class = "ms-auto"),
      shiny::span(
        id = paste0(status_id, "-tokens-input"),
        class = "shidashi-chatbot-status-counter",
        title = "Input tokens",
        "\u2191 0"  # up arrow
      ),
      shiny::span(
        id = paste0(status_id, "-tokens-output"),
        class = "shidashi-chatbot-status-counter",
        title = "Output tokens",
        "\u2193 0"  # down arrow
      ),
      shiny::span(
        id = paste0(status_id, "-cost"),
        class = "shidashi-chatbot-status-counter",
        title = "Estimated cost",
        "$0"
      )
    )
  )
}


# chatbot_drawer_ui() has been removed.
# The drawer shell is now provided by module_drawer() in drawer.R.
# Drawer content is rendered via shiny::renderUI in the module server.


# ---- Server component ----

#' Chat-bot server logic (per-module)
#'
#' @description
#' Sets up the chat server for a single module.
#' Creates its own \code{\link[ellmer]{Chat}} object, binds tools from
#' the \verb{MCP} session registry, and manages per-module conversation
#' history.
#'
#' The function renders \code{\link{chatbot_ui}()} into the drawer's
#' \code{uiOutput} via \code{shiny::renderUI}, and opens the drawer
#' when a \code{"button.click"} shidashi-event with
#' \code{type = "open_drawer"} is received.
#' Any element with \code{data-shidashi-action="shidashi-button"}
#' \code{data-shidashi-type="open_drawer"} can trigger the drawer.
#'
#' This function is injected into each module's server function by
#' \code{modules.R} when \code{agents.yaml} has \code{enabled: yes}.
#' It is called inside \code{shiny::moduleServer()}, so \code{session}
#' is module-scoped.  \pkg{shinychat} operations use the scoped
#' \code{session}; only drawer and event operations use
#' \code{session$rootScope()}.
#'
#' @param input,output,session Standard Shiny server arguments
#'   (typically module-scoped when inside \code{moduleServer}).
#' @param id character; must match the \code{id} used in
#'   \code{chatbot_ui()}. Default \code{"shidashi-chatbot"}.
#' @param drawer_id character; the output ID of the drawer's
#'   \code{uiOutput} placeholder (from \code{\link{module_drawer}()}).
#'   Default \code{"shidashi_drawer"}.
#' @param agent_conf list; parsed \code{agents.yaml} content. Used
#'   for the system prompt and tool configuration.
#' @return Called for side effects (sets up observers). Returns
#'   \code{invisible(NULL)}.
#' @keywords internal
chatbot_server <- function(input, output, session,
                           id = "shidashi-chatbot",
                           drawer_id = "shidashi_drawer",
                           agent_conf = NULL) {
  # Guard: disabled or missing deps
  if (!isTRUE(getOption("shidashi.chatbot", TRUE))) {
    return(invisible(NULL))
  }
  if (!requireNamespace("shinychat", quietly = TRUE)) {
    return(invisible(NULL))
  }
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    return(invisible(NULL))
  }

  # Observe shidashi button events
  event_data <- register_session_events(session)

  # Module ID from the calling moduleServer namespace
  module_id <- session$ns(NULL)
  if (!length(module_id) || !nzchar(module_id)) {
    module_id <- "__root__"
  }

  # Handle user input from shinychat (scoped session)
  user_input_id <- paste0(id, "_user_input")

  # Conversation selector change
  conv_select_id <- paste0(id, "-conv_select")

  # New conversation button
  new_conv_id <- paste0(id, "-new_conversation")

  # Mode selector change
  mode_select_id <- paste0(id, "-mode_select")

  # Confirmation policy selector
  confirm_policy_id <- paste0(id, "-confirm_policy")

  # Stop button
  stop_btn_id <- paste0(id, "-stop")

  # ---- Local state (fastmap for non-reactive mutable state) ----
  local_data <- fastmap::fastmap()
  local_data$set("chat_token", NULL)
  local_data$set("is_streaming", FALSE)

  # Generate a new chat token (invalidates any in-flight operations)
  new_chat_token <- function() {
    token <- paste0(Sys.time(), "-", rand_string())
    local_data$set("chat_token", token)
    token
  }

  # Check if a token is still valid (matches current)
  is_token_valid <- function(token) {
    isTRUE(token == local_data$get("chat_token"))
  }

  # ---- Mode state ----
  agent_conf <- as.list(agent_conf)
  agent_modes <- agent_conf$modes %||% "None"
  agent_default_mode <- agent_conf$parameters$default_mode %||% agent_modes[[1]]
  globals_set_agent_mode(module_id = module_id, mode = agent_default_mode)
  current_mode <- shiny::reactiveVal(agent_default_mode)

  # ---- Render chatbot UI into the drawer's uiOutput ----
  output[[drawer_id]] <- shiny::renderUI({
    chatbot_ui(id = session$ns(id),
               modes = agent_modes,
               default_mode = agent_default_mode)
  })

  # ---- Per-module Chat object (created lazily) ----

  local_chat <- NULL

  ensure_chat <- function() {
    if (!is.null(local_chat)) return(local_chat)

    # Generate initial token for this chat session
    new_chat_token()

    tryCatch(
      {
        chat <- globals_new_chat(module_id = module_id, session = session)

        chat$on_tool_request(function(request) {
          if (!is_token_valid(local_data$get("callback_token"))) {
            ellmer::tool_reject(reason = paste(
              "Callback token has changed.",
              "User has terminated current conversation.",
              "You should NOT make any tool calls and stop immediately."
            ))
          }
        })

        # Capture current token for tool result callback
        chat$on_tool_result(function(result) {
          # Check if chat was stopped/reset - silently drop if so
          if (!is_token_valid(local_data$get("callback_token"))) {
            return(invisible(NULL))
          }
          tryCatch({
            # if (!is.null(result@request) && endsWith(result@request@name, "shiny_query_ui")) {
            #   return(invisible(NULL))
            # }
            if (
              S7::S7_inherits(result@value, ellmer::ContentImage)
            ) {
              img_type <- result@value@type
              img_data <- result@value@data
              result <- sprintf("<img src='data:%s;base64,%s' style='max-width:100%%' />", img_type, img_data)
            }
            shinychat::chat_append(id = id, session = session, result)
          }, error = function(e) {
            print(result)
            warning(e)
          })
          return()
        })

        # Send provider/model info to the status bar
        provider <- chat$get_provider()
        session$sendCustomMessage(
          "shidashi.update_chat_status",
          list(
            id     = session$ns(paste0(id, "-status-model")),
            text   = sprintf("%s/%s", provider@name, provider@model),
            status = "ready"
          )
        )

        # Initialize stop button in the chat input area
        session$sendCustomMessage(
          "shidashi.init_chat_stop_button",
          list(
            chat_id = session$ns(id),
            stop_id = session$ns(stop_btn_id)
          )
        )

        # Initialize code copy buttons for pre blocks
        session$sendCustomMessage(
          "shidashi.init_chat_code_copy",
          list(chat_id = session$ns(id))
        )

        # Share chat object
        local_chat <<- chat
        chat
      },
      error = function(e) {
        shinychat::chat_append(
          id = id,
          session = session,
          response = sprintf(
            "[shidashi] Failed to create chat: \n\n```\n%s\n```\n",
            paste(conditionMessage(e), collapse = "\n")
          ),
          role = "assistant"
        )
        NULL
      }
    )

  }

  get_tokens <- function() {
    res <- list(input = 0L, output = 0L, cached = 0L, cost = NA_real_)
    if (!inherits(local_chat, "Chat")) { return(res) }
    tokens <- local_chat$get_tokens()
    if (!length(tokens)) { return(res) }

    res$output <- sum(c(tokens$output, 0), na.rm = TRUE)
    res$input <- sum(c(tokens$input, 0), na.rm = TRUE)
    if (length(tokens$cached_input)) {
      res$cached <- tokens$cached_input[[length(tokens$cached_input)]]
    }

    res$cost <- tryCatch(
      local_chat$get_cost(),
      error = function(e)
        NA_real_
    )
    res
  }

  update_chat_status <- function(status = "ready") {
    # Update stop button visibility
    session$sendCustomMessage(
      "shidashi.toggle_stop_button",
      list(
        id = session$ns(stop_btn_id),
        visible = (status == "recalculating")
      )
    )
    if (!inherits(local_chat, "Chat")) { return() }
    tokens <- get_tokens()
    ns_prefix <- session$ns(paste0(id, "-status"))

    # Input tokens
    cached_note <- ""
    if (tokens$cached > 0L) {
      cached_note <- sprintf(" (%s cached)", format_token(tokens$cached))
    }
    session$sendCustomMessage(
      "shidashi.update_chat_status",
      list(
        id     = paste0(ns_prefix, "-tokens-input"),
        text   = paste0("\u2191 ", format_token(tokens$input + tokens$cached)),
        title  = paste0("Input tokens", cached_note),
        status = status
      )
    )
    # Output tokens
    session$sendCustomMessage(
      "shidashi.update_chat_status",
      list(
        id     = paste0(ns_prefix, "-tokens-output"),
        text   = paste0("\u2193 ", format_token(tokens$output)),
        title  = "Output tokens",
        status = status
      )
    )
    # Cost
    session$sendCustomMessage(
      "shidashi.update_chat_status",
      list(
        id     = paste0(ns_prefix, "-cost"),
        text   = format_cost(tokens$cost),
        title  = if (is.na(tokens$cost)) "Token pricing unknown" else "Estimated cost",
        status = if (is.na(tokens$cost)) "unknown" else status
      )
    )
  }

  # ---- Conversation-dropdown helpers ----
  # Push current conversation list into the selectInput dropdown
  update_conv_dropdown <- function() {
    entry <- globals_get_conversation_entry(module_id = module_id)
    choices <- seq_along(entry$conversations)
    names(choices) <- vapply(entry$conversations, function(c) {
      paste(c$title %||% "New conversation", collapse = " ")
    }, character(1))
    shiny::updateSelectInput(
      session  = session,
      inputId  = paste0(id, "-conv_select"),
      choices  = choices,
      selected = as.character(entry$active_idx)
    )
  }

  # ---- ExtendedTask for streaming chat ----
  chat_task <- shiny::ExtendedTask$new(coro::async(function(user_msg) {
    ensure_chat()
    if (is.null(local_chat)) {
      return(NULL)
    }

    # Capture token at request start for validation in callbacks
    request_token <- local_data$get("chat_token")
    local_data$set("callback_token", request_token)
    local_data$set("is_streaming", TRUE)

    update_chat_status(status = "recalculating")

    stream <- local_chat$stream_async(
      user_msg,
      tool_mode = "sequential",
      stream = "text"
    )

    tryCatch(
      {
        user_stopped <- FALSE
        while (TRUE) {
          if (is_token_valid(request_token)) {
            content <- coro::await(stream())
          } else {
            stream(close = TRUE)
            user_stopped <- TRUE
            content <- coro::exhausted()
          }

          if (user_stopped) {
            shinychat::chat_append(
              id,
              response = "\n\n*[Generation stopped by user]*",
              role = "assistant",
              session = session
            )
          } else if (!coro::is_exhausted(content)) {
            shinychat::chat_append_message(
              id = id,
              msg = list(role = "assistant", content = content),
              chunk = "end",
              operation = "append"
            )
          } else {
            # Make sure to end the message to reenable the chatbox
            shinychat::chat_append_message(
              id = id,
              msg = list(role = "assistant", content = ""),
              chunk = "end",
              operation = "append"
            )
          }

          if (coro::is_exhausted(content)) {
            request_token <- "N/A"
            local_data$set("callback_token", request_token)
            local_data$set("is_streaming", FALSE)
            break
          }
        }
      },
      error = function(e) {
        shinychat::chat_append(
          id,
          response = sprintf(
            "Error %s",
            paste(cli::ansi_strip(conditionMessage(e)), collapse = " ")
          ),
          role = "assistant",
          session = session
        )
      }
    ) # tryCatch

    # Runs after the stream is fully consumed -> tokens are available
    globals_save_conversation(module_id = module_id, chat = local_chat)
    update_conv_dropdown()
    update_chat_status()

  }))

  # ---- Observers ----

  # On user prompt
  shiny::bindEvent(
    shiny::observe({
      user_msg <- paste(input[[user_input_id]], collapse = "")
      user_msg <- trimws(user_msg)
      if (!nzchar(user_msg)) { return() }
      chat_task$invoke(user_msg)
    }),
    input[[user_input_id]],
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )

  # On switching conversation ID
  shiny::bindEvent(
    shiny::observe({

      selected <- as.integer(input[[conv_select_id]])
      if (length(selected) != 1 || is.na(selected)) return()

      entry <- globals_get_conversation_entry(module_id = module_id)
      if (
        selected < 1L ||
        selected > length(entry$conversations) ||
        isTRUE(entry$active_idx == selected)) {

        # no need to change
        return()
      }

      # Invalidate any pending operations from previous conversation
      new_chat_token()

      # Save current conversation before switching
      globals_save_conversation(module_id = module_id, chat = local_chat)

      # Switch conversation
      entry$active_idx <- selected
      globals_set_conversation_entry(entry = entry, module_id = module_id)

      # restore chat
      ensure_chat()
      if (is.null(local_chat)) return()

      # Load the selected conversation's turns into local_chat
      conv <- entry$conversations[[selected]]
      if (length(conv$turns)) {
        local_chat$set_turns(conv$turns)
      } else {
        local_chat$set_turns(list())
      }

      # Update the chat widget
      shinychat::chat_clear(id = id, session = session)

      # as of 0.3.0, chat_restore does not work as expected and throws
      # S7 error. Manually restore text instead
      # shinychat::chat_restore
      lapply(
        local_chat$get_turns(include_system_prompt = FALSE),
        function(turn) {
          tryCatch(
            {
              shinychat::chat_append(
                id = id,
                response = turn@text,
                role = turn@role,
                session = session
              )
            },
            error = function(e) {
              # pass
            }
          )
        }
      )
      return()

    }),
    input[[conv_select_id]],
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )

  # On starting new conversation
  shiny::bindEvent(
    shiny::observe({

      # Invalidate any pending operations from previous conversation
      new_chat_token()

      # Save current conversation before starting a new one
      globals_save_conversation(module_id = module_id, chat = local_chat)

      chat <- ensure_chat()
      if (is.null(chat)) return()

      # Already saved, hence save_first = FALSE
      globals_new_conversation(module_id = module_id,
                               chat = chat,
                               save_first = FALSE)

      # Clear the UI
      shinychat::chat_clear(id = id, session = session)
      update_conv_dropdown()

    }),
    input[[new_conv_id]],
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )

  # On stop button click
  shiny::bindEvent(
    shiny::observe({
      if (!isTRUE(local_data$get("is_streaming"))) return()

      # Invalidate current token - this causes all in-flight operations
      # to be silently dropped when they check their captured token
      new_chat_token()
      local_data$set("is_streaming", FALSE)

      # Save whatever we have and update UI
      globals_save_conversation(module_id = module_id, chat = local_chat)
      update_conv_dropdown()
      update_chat_status(status = "ready")
    }),
    input[[stop_btn_id]],
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )

  # On changing permission mode
  shiny::bindEvent(
    shiny::observe({
      new_mode <- input[[mode_select_id]]
      if (length(new_mode) != 1 || !nzchar(new_mode)) return()
      current_mode(new_mode)

      # Sync mode into globals so MCP handler can read it
      globals_set_agent_mode(module_id = module_id, mode = new_mode)

      if (!inherits(local_chat, "Chat")) { return() }

      globals_bind_chat_tools(chat = local_chat,
                              module_id = module_id,
                              session = session)

    }),
    input[[mode_select_id]],
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )

  # On changing confirmation policy
  shiny::bindEvent(
    shiny::observe({
      policy <- input[[confirm_policy_id]]
      if (!length(policy) || !nzchar(policy)) return()
      globals_set_confirmation_policy(module_id = module_id, policy = policy)
    }),
    input[[confirm_policy_id]],
    ignoreNULL = TRUE,
    ignoreInit = TRUE
  )

  # Save conversation on session end
  shiny::onSessionEnded(fun = function() {
    globals_save_conversation(module_id = module_id, chat = local_chat)
  }, session = session)

  invisible(NULL)
}
