# ---- In-App Chatbot (ellmer + shinychat) ----
#
# Phase 6 of the agent integration.
# Provides init_chat(), chatbot_ui(), and chatbot_server() for
# per-module AI chat inside the drawer panel.
#
# Design:
#   - Drawers are module-level (inside each module iframe).
#   - module_drawer() emits a minimal shell with uiOutput().
#   - chatbot_server() renders chatbot_ui() into that uiOutput
#     via standard shiny::renderUI — no special frontend needed.
#   - A shidashi-button event ("open_drawer") is fired by the FAB;
#     chatbot_server() observes it and calls drawer_open().
#   - Any element with data-shidashi-action="shidashi-button"
#     data-shidashi-type="open_drawer" can trigger the drawer.
#   - Each module creates its own ellmer::Chat in its closure.
#   - Per-module conversation history stored in
#     .__shidashi_globals__.$module_conversations (fastmap).
#   - Tools bound from MCP session registry via chat$set_tools().

# ---- Provider dispatch ----

#' Create an \pkg{ellmer} Chat object for the chat-bot
#'
#' @description
#' Factory function that creates an \code{ellmer::Chat} object based on
#' the configured provider.  Reads from
#' \code{options(shidashi.chat_provider)}, \code{shidashi.chat_model},
#' and \code{shidashi.chat_base_url}. These arguments are passed to
#' \code{\link[ellmer]{chat}}.
#'
#' @param system_prompt character; the system prompt.  Defaults to
#'   \code{getOption("shidashi.chat_system_prompt")}.
#' @param provider character; provider name or provider name with models.
#'   Defaults to \code{getOption("shidashi.chat_provider", "anthropic")}.
#' @param base_url character or \code{NULL}; base URL for
#'   API-compatible providers.
#' @return An \code{ellmer::Chat} R6 object (tools not yet bound).
#' @keywords internal
init_chat <- function(
  system_prompt = getOption("shidashi.chat_system_prompt", NULL),
  provider = getOption("shidashi.chat_provider", "anthropic"),
  # model = getOption("shidashi.chat_model", NULL),
  base_url = getOption("shidashi.chat_base_url", NULL)
) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Package 'ellmer' is required for the chatbot feature.")
  }

  if (!length(system_prompt)) {
    system_prompt <- paste(
      "You are an R Shiny expert. You have access to the shiny",
      "application via provided tools."
    )
  }

  provider <- tolower(provider)

  # Build args common to most providers
  args <- list(system_prompt = system_prompt, name = provider, echo = "all")
  # if (length(model) == 1L && nzchar(model)) {
  #   args$model <- model
  # }
  if (length(base_url) == 1L && nzchar(base_url)) {
    args$base_url <- base_url
  }
  do.call(ellmer::chat, args)
}


# ---- UI component ----

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
chatbot_ui <- function(id) {
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
  shiny::tagList(
    shiny::div(
      class = "shidashi-chatbot-header d-flex align-items-center px-2 py-1 gap-1",
      shiny::div(
        class = "shidashi-chatbot-conv-select flex-grow-1",
        shiny::selectInput(
          conv_select_id,
          label = NULL,
          choices = c("New conversation" = "1"),
          width = "100%"
        )
      ),
      shiny::actionLink(
        new_conv_id, label = NULL,
        icon = shiny::icon("plus"),
        title = "New conversation",
        class = "shidashi-chatbot-new-conv btn btn-sm btn-outline-secondary"
      )
    ),
    shinychat::chat_ui(id, fill = TRUE)
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
    module_id <- "unknown"
  }

  # ---- Render chatbot UI into the drawer's uiOutput ----
  output[[drawer_id]] <- shiny::renderUI({
    chatbot_ui(id = session$ns(id))
  })

  # ---- Per-module Chat object (created lazily) ----

  local_chat <- NULL

  ensure_chat <- function() {
    if (!is.null(local_chat)) return(local_chat)
    system_prompt <- if (is.list(agent_conf)) {
      agent_conf$parameters$system_prompt
    }
    local_chat <<- tryCatch(
      init_chat(system_prompt = system_prompt),
      error = function(e) {
        show_notification(
          title = "[shidashi] Failed to create chat",
          message = conditionMessage(e),
          type = "warning"
        )
        NULL
      }
    )
    if (is.null(local_chat)) return(NULL)

    # Bind tools from MCP registry
    bind_tools_from_registry(local_chat, session)

    # Restore active conversation
    globals <- tryCatch(get_shidashi_globals(), error = function(e) NULL)
    if (!is.null(globals)) {
      restore_turns(globals, module_id, local_chat)
    }

    local_chat
  }

  # ---- Conversation-history helpers ----

  # Derive a short title from the first user turn (max 30 chars)
  conversation_title <- function(turns) {
    if (!length(turns)) return("New conversation")
    txt <- turns[[1]]@text
    if (nchar(txt) > 30L) {
      txt <- paste0(substr(txt, 1L, 27L), "...")
    }
    return(txt)
  }

  # Ensure module_conversations entry exists and return it
  ensure_conv_entry <- function(globals, mid) {
    entry <- globals$module_conversations$get(mid)
    if (is.null(entry)) {
      entry <- list(
        active_idx = 1L,
        conversations = list(
          list(
            title = "New conversation",
            turns = list(),
            last_visited = Sys.time()
          )
        )
      )
      globals$module_conversations$set(mid, entry)
    }
    entry
  }

  # Save current turns into the active conversation slot
  save_turns <- function(globals, mid, chat) {
    if (!length(mid) || !nzchar(mid) || is.null(chat)) return()
    turns <- tryCatch(chat$get_turns(), error = function(e) NULL)
    if (!length(turns)) return()

    entry <- ensure_conv_entry(globals, mid)
    idx   <- entry$active_idx
    entry$conversations[[idx]] <- list(
      title        = conversation_title(turns),
      turns        = turns,
      last_visited = Sys.time()
    )
    globals$module_conversations$set(mid, entry)
  }

  # Restore turns from the active conversation slot
  restore_turns <- function(globals, mid, chat) {
    entry <- ensure_conv_entry(globals, mid)
    idx   <- entry$active_idx
    conv  <- entry$conversations[[idx]]
    if (!is.null(conv) && length(conv$turns)) {
      chat$set_turns(conv$turns)
    } else {
      chat$set_turns(list())
    }
  }

  # Bind tools from the MCP session registry
  bind_tools_from_registry <- function(chat, sess) {
    globals <- tryCatch(get_shidashi_globals(), error = function(e) NULL)
    if (is.null(globals)) return()

    token <- sess$token
    if (!length(token) || !nzchar(token)) return()

    registry <- globals$mcp_session_registry
    entry <- registry$get(token)
    if (is.list(entry) && length(entry$tools)) {
      enabled_tools <- Filter(function(t) {
        isTRUE(t@annotations$shidashi_enabled)
      }, entry$tools)
      if (length(enabled_tools)) {
        chat$set_tools(enabled_tools)
      }
    }
  }

  # ---- Conversation-dropdown helpers ----

  # Push current conversation list into the selectInput dropdown
  update_conv_dropdown <- function() {
    globals <- tryCatch(get_shidashi_globals(), error = function(e) NULL)
    if (is.null(globals)) return()
    entry   <- ensure_conv_entry(globals, module_id)
    choices <- seq_along(entry$conversations)
    names(choices) <- vapply(entry$conversations, function(c) {
      c$title %||% "New conversation"
    }, character(1))
    shiny::updateSelectInput(
      session  = session,
      inputId  = paste0(id, "-conv_select"),
      choices  = choices,
      selected = as.character(entry$active_idx)
    )
  }

  # ---- ExtendedTask for streaming chat ----

  chat_task <- shiny::ExtendedTask$new(function(user_msg) {
    chat <- ensure_chat()
    if (is.null(chat)) return(promises::promise_resolve(NULL))

    globals <- tryCatch(get_shidashi_globals(), error = function(e) NULL)

    promises::promise(function(resolve, reject) {
      resolve(chat$stream_async(
        user_msg,
        tool_mode = "sequential",
        stream = "text"
      ))
    })$then(
      onFulfilled = function(stream) {
        save_turns(globals, module_id, local_chat)
        update_conv_dropdown()
        shinychat::chat_append(id, stream, session = session)
      }
    )$catch(onRejected = function(e) {
      save_turns(globals, module_id, local_chat)
      update_conv_dropdown()
      shinychat::chat_append(
        id,
        response = sprintf(
          "Error %s",
          paste(cli::ansi_strip(conditionMessage(e)), collapse = " ")
        ),
        role = "assistant",
        session = session
      )
    })
  })

  # ---- Observers ----

  # Handle user input from shinychat (scoped session)
  user_input_id <- paste0(id, "_user_input")

  shiny::observeEvent(input[[user_input_id]], {
    user_msg <- input[[user_input_id]]
    if (!length(user_msg) || !nzchar(user_msg)) return()
    chat_task$invoke(user_msg)
  }, ignoreNULL = TRUE, ignoreInit = TRUE)

  # Conversation selector change
  conv_select_id <- paste0(id, "-conv_select")

  shiny::observeEvent(input[[conv_select_id]], {
    tryCatch(
      {
        selected <- as.integer(input[[conv_select_id]])
        if (is.na(selected)) return()

        globals <- get_shidashi_globals()
        if (is.null(globals)) return()

        chat <- ensure_chat()
        if (is.null(chat)) return()

        # Save current conversation before switching
        save_turns(globals, module_id, chat)

        entry <- ensure_conv_entry(globals, module_id)
        if (selected < 1L || selected > length(entry$conversations)) return()
        entry$active_idx <- selected
        globals$module_conversations$set(module_id, entry)

        # Restore turns from selected conversation
        restore_turns(globals, module_id, chat)

        # Update the chat widget
        shinychat::chat_clear(id = id, session = session)
        shinychat::chat_restore
        lapply(chat$get_turns(include_system_prompt = FALSE), function(turn) {
          shinychat::chat_append(
            id = id,
            response = turn@text,
            role = turn@role,
            session = session
          )
        })
        return()
      },
      error = function(e) {
        warning(e)
        traceback(e)
      }
    )

  }, ignoreInit = TRUE)

  # New conversation button
  new_conv_id <- paste0(id, "-new_conversation")

  shiny::observeEvent(input[[new_conv_id]], {
    chat <- ensure_chat()
    if (is.null(chat)) return()

    globals <- tryCatch(get_shidashi_globals(), error = function(e) NULL)
    if (is.null(globals)) return()

    # Save current conversation before starting a new one
    save_turns(globals, module_id, chat)

    # Append a new empty conversation and make it active
    entry <- ensure_conv_entry(globals, module_id)
    entry$conversations <- c(entry$conversations, list(list(
      title        = "New conversation",
      turns        = list(),
      last_visited = Sys.time()
    )))
    entry$active_idx <- length(entry$conversations)
    globals$module_conversations$set(module_id, entry)

    # Clear the Chat turns and UI
    chat$set_turns(list())
    shinychat::chat_clear(id = id, session = session)

    update_conv_dropdown()
  }, ignoreInit = TRUE)

  # Save conversation on session end
  shiny::onSessionEnded(fun = function() {
    if (!is.null(local_chat)) {
      globals <- tryCatch(get_shidashi_globals(), error = function(e) NULL)
      if (!is.null(globals)) {
        save_turns(globals, module_id, local_chat)
      }
    }
  }, session = session)

  invisible(NULL)
}
