library(shiny)
library(shidashi)

# ---------------------------------------------------------------------------
# Section 1 — Session Info
# ---------------------------------------------------------------------------

ui_session_info <- function() {
  tagList(
    h3("Session Registry", class = "shidashi-anchor mt-0"),
    p(
      class = "inline-all",
      tags$code("register_session(session)"), " stores each Shiny module session ",
      "in a global registry keyed by ", tags$code("session$token"), ". ",
      "The registry entry holds the ", tags$code("shared_id"), " (resolved from ",
      "the URL query string or auto-generated), the session object itself, ",
      "a reactive event bus, and MCP tool bindings."
    ),
    fluidRow(
      column(
        width = 6L,
        card(
          title = "Registry Entry for This Session",
          class_body = "min-height-200",
          tools = list(
            card_tool(widget = "collapse")
          ),
          body_main = div(
            p(
              class = "inline-all",
              "The entry below is read directly from ",
              tags$code("globals_session_registry()"), " via ",
              tags$code("shidashi:::get_session_entry(session$token)"), "."
            ),
            verbatimTextOutput(ns("session_entry_info"))
          ),
          footer = actionButton(
            ns("refresh_entry"),
            label = "Refresh",
            class = "btn-sm btn-outline-primary"
          )
        )
      ),
      column(
        width = 6L,
        card(
          title = "register_session() — shared_id resolution",
          class_body = "min-height-200",
          tools = list(
            card_tool(widget = "collapse")
          ),
          body_main = div(
            p(
              class = "inline-all",
              tags$code("register_session(session)"), " reads ",
              tags$code("shared_id"), " directly from the URL query string ",
              "(\u0060?shared_id=my_id\u0060) or generates a random string. ",
              "It is stored in the session registry entry and accessible via ",
              tags$code("shidashi:::get_session_entry(session$token)$shared_id"), "."
            ),
            html_highlight_code(
              {
                # In module server:
                shidashi::register_session(session)
                # shared_id is resolved from:
                #   1. ?shared_id= query param (URL)
                #   2. auto-generated random string
                # It is stored in the session registry entry.
                shidashi::fire_event("demo.ping", list(ts = Sys.time()))
              },
              width.cutoff = 30L, hover = "overflow-auto"
            )
          )
        )
      )
    )
  )
}

# ---------------------------------------------------------------------------
# Section 2 — Local Events
# ---------------------------------------------------------------------------

ui_local_events <- function() {
  tagList(
    hr(),
    h3("Local Events", class = "shidashi-anchor"),
    p(
      class = "inline-all",
      tags$code("fire_event(key, value)"), " stores a reactive value on the ",
      "current session's event bus. ",
      tags$code("get_event(key)"), " reads it back within a reactive context. ",
      "Events are scoped to the session by default (", tags$code("global = FALSE"), ")."
    ),
    fluidRow(
      column(
        width = 6L,
        card(
          title = "fire_event / get_event",
          class_body = "min-height-250",
          tools = list(
            card_tool(widget = "collapse")
          ),
          body_main = div(
            html_highlight_code(
              {
                shidashi::fire_event("my.key", list(value = 42, ts = Sys.time()))
                evt <- shidashi::get_event("my.key")
                evt$value  # 42
              },
              width.cutoff = 30L, hover = "overflow-auto"
            ),
            hr(),
            fluidRow(
              column(6L, numericInput(ns("local_value"), "Value to send", value = 1, min = 1)),
              column(6L, textInput(ns("local_key"), "Event key", value = "demo.local"))
            )
          ),
          footer = fluidRow(
            column(
              6L,
              actionButton(ns("fire_local"), "fire_event()",
                           class = "btn-sm btn-primary w-100")
            ),
            column(
              6L,
              actionButton(ns("read_local"), "get_event()",
                           class = "btn-sm btn-outline-secondary w-100")
            )
          )
        )
      ),
      column(
        width = 6L,
        card(
          title = "Local Event Log",
          class_body = "height-300 overflow-auto",
          tools = list(
            card_tool(widget = "collapse")
          ),
          body_main = verbatimTextOutput(ns("local_event_log"))
        )
      )
    )
  )
}

# ---------------------------------------------------------------------------
# Section 3 — Global (Cross-Tab) Events
# ---------------------------------------------------------------------------

ui_global_events <- function() {
  tagList(
    hr(),
    h3("Global Events (Cross-Tab Broadcasting)", class = "shidashi-anchor"),
    p(
      class = "inline-all",
      "When ", tags$code("global = TRUE"), " is passed to ",
      tags$code("fire_event()"), ", the event is propagated to ",
      tags$em("all"), " live sessions that share the same ",
      tags$code("shared_id"), ". Open this module in a second browser tab ",
      "and click the button — both tabs will receive the event."
    ),
    p(
      class = "inline-all text-muted",
      "Tabs share a ", tags$code("shared_id"), " when they open the same ",
      "shidashi dashboard URL. You can also pin a specific ",
      tags$code("shared_id"), " via the URL query string: ",
      tags$code("?shared_id=your_id"), "."
    ),
    fluidRow(
      column(
        width = 6L,
        card(
          title = "Broadcast a Global Event",
          class_body = "min-height-250",
          tools = list(
            card_tool(widget = "collapse")
          ),
          body_main = div(
            html_highlight_code(
              {
                shidashi::fire_event(
                  key    = "global.ping",
                  value  = list(message = "Hello from another tab!", ts = Sys.time()),
                  global = TRUE     # broadcast to all tabs with same shared_id
                )
              },
              width.cutoff = 30L, hover = "overflow-auto"
            ),
            hr(),
            textInput(ns("global_message"), "Message to broadcast",
                      value = "Hello from this tab!"),
            div(
              class = "text-muted small mt-2",
              "Shared ID: ", textOutput(ns("shared_id_display"), inline = TRUE)
            )
          ),
          footer = actionButton(ns("fire_global"), "Broadcast: fire_event(global=TRUE)",
                                class = "btn-sm btn-warning w-100")
        )
      ),
      column(
        width = 6L,
        card(
          title = "Received Global Events",
          class_body = "height-300 overflow-auto",
          tools = list(
            card_tool(widget = "collapse")
          ),
          body_main = div(
            p(
              class = "text-muted small inline-all",
              "This panel updates reactively whenever a ", tags$code("global.ping"),
              " event arrives — on any tab."
            ),
            verbatimTextOutput(ns("global_event_log"))
          )
        )
      )
    )
  )
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server_session_events <- function(input, output, session, ...) {

  shidashi::register_session(session)

  # Keep a local log of events (not reactive — just a character vector in a
  # reactiveVal so we can append to it)
  local_log  <- reactiveVal(character(0))
  global_log <- reactiveVal(character(0))

  # ---- Section 1: session registry info ----------------------------------

  entry_info <- reactiveVal(NULL)

  get_entry <- function() shidashi:::get_session_entry(session$token)

  # Populate on load
  observe({
    entry <- get_entry()
    token <- session$token
    if (is.null(entry)) {
      entry_info("(session not yet in registry)")
      return()
    }
    entry_info(paste(
      paste0("token:      ", token),
      paste0("shared_id:  ", entry$shared_id),
      paste0("namespace:  ", entry$namespace),
      paste0("registered: ", format(entry$registered_at, "%Y-%m-%d %H:%M:%S")),
      sep = "\n"
    ))
  })

  observeEvent(input$refresh_entry, {
    entry <- get_entry()
    token <- session$token
    if (is.null(entry)) {
      entry_info("(session entry not found)")
      return()
    }
    entry_info(paste(
      paste0("token:      ", token),
      paste0("shared_id:  ", entry$shared_id),
      paste0("namespace:  ", entry$namespace),
      paste0("registered: ", format(entry$registered_at, "%Y-%m-%d %H:%M:%S")),
      paste0("mcp_tools:  ", entry$tools$size()),
      sep = "\n"
    ))
  })

  output$session_entry_info <- renderText({
    entry_info() %||% "(loading...)"
  })

  # ---- Section 2: local events -------------------------------------------

  output$shared_id_display <- renderText({
    entry <- shidashi:::get_session_entry(session$token)
    if (is.null(entry)) "(unknown)" else entry$shared_id
  })

  observeEvent(input$fire_local, {
    key   <- trimws(input$local_key)
    value <- as.integer(input$local_value)
    if (!nzchar(key)) {
      show_notification("Event key must not be empty.", type = "warning")
      return()
    }
    fire_event(key = key, value = list(value = value, ts = Sys.time()), session = session)
    line <- sprintf("[%s] fired '%s' = %s", format(Sys.time(), "%H:%M:%S"), key, value)
    local_log(c(local_log(), line))
  })

  observeEvent(input$read_local, {
    key <- trimws(input$local_key)
    if (!nzchar(key)) {
      show_notification("Event key must not be empty.", type = "warning")
      return()
    }
    evt <- get_event(key = key, session = session)
    if (is.null(evt)) {
      line <- sprintf("[%s] get_event('%s') -> NULL (not yet fired)", format(Sys.time(), "%H:%M:%S"), key)
    } else {
      line <- sprintf("[%s] get_event('%s') -> value=%s ts=%s",
                      format(Sys.time(), "%H:%M:%S"), key,
                      evt$value %||% "?",
                      format(evt$ts, "%H:%M:%S"))
    }
    local_log(c(local_log(), line))
  })

  output$local_event_log <- renderText({
    log <- local_log()
    if (!length(log)) return("(no events yet — fire one above)")
    paste(rev(log), collapse = "\n")
  })

  # ---- Section 3: global events ------------------------------------------

  observeEvent(input$fire_global, {
    msg <- trimws(input$global_message)
    if (!nzchar(msg)) msg <- "(empty message)"
    fire_event(
      key    = "global.ping",
      value  = list(message = msg, ts = Sys.time(),
                    from_tab = session$token),
      global = TRUE,
      session = session
    )
  })

  # React to the global.ping event arriving on this session
  shidashi::register_session(session)

  observe({
    evt <- get_event("global.ping", session = session)
    if (is.null(evt)) return()
    line <- sprintf("[%s] from_tab=%s | \"%s\"",
                    format(evt$ts %||% Sys.time(), "%H:%M:%S"),
                    substr(evt$from_tab %||% "?", 1, 8),
                    evt$message %||% "(no message)")
    # isolate() prevents global_log from being a reactive dependency of this
    # observer — without it, writing global_log() re-triggers this observe,
    # causing an infinite loop.
    global_log(c(isolate(global_log()), line))
  })

  output$global_event_log <- renderText({
    log <- global_log()
    if (!length(log)) return("(no global events yet — click broadcast above, or open a second tab)")
    paste(rev(log), collapse = "\n")
  })
}
