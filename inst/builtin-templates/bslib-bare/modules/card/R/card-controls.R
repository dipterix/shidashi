
ui_card_controls <- function() {
  tagList(

    # --- 1. Server-side tabset control ---
    shiny::column(
      width = 4L,
      card(
        title = "Tabset Control",
        class_body = "no-padding",
        shiny::div(
          class = "p-3",
          p(
            "Use ", tags$code("card_tabset_activate()"), " and ",
            tags$code("card_tabset_insert()"), " to control a cardset ",
            "from the server."
          ),
          shiny::fluidRow(
            shiny::column(6L,
              actionButton(ns("switch_tab_a"), "Activate Tab A",
                           class = "btn-primary btn-sm w-100 mb-2")
            ),
            shiny::column(6L,
              actionButton(ns("add_tab_a"), "Insert Random Tab",
                           class = "btn-secondary btn-sm w-100 mb-2")
            )
          ),
          html_highlight_code(
            {
              # Activate a specific tab
              card_tabset_activate("card_control_1", title = "Tab A")

              # Insert / remove a tab dynamically
              card_tabset_insert("card_control_1", title = "Tab X",
                                 p("Dynamic content"))
            },
            width.cutoff = 20L, hover = "overflow-auto"
          )
        )
      ),
      card_tabset(
        inputId = ns("card_control_1"),
        title = "Controlled Cardset",
        class_body = "min-height-150",
        "Tab A" = p("Content of Tab A"),
        "Tab B" = p("Content of Tab B")
      )
    ),

    # --- 2. Server-side card2 control ---
    shiny::column(
      width = 4L,
      card(
        title = "Card2 (B-side) Control",
        class_body = "no-padding",
        shiny::div(
          class = "p-3",
          p(
            "Use ", tags$code("card2_open()"), ", ",
            tags$code("card2_close()"), ", or ",
            tags$code("card2_toggle()"), " to open or close the B-side panel."
          ),
          shiny::fluidRow(
            shiny::column(4L,
              actionButton(ns("card_control_2_open"), "Open",
                           class = "btn-success btn-sm w-100 mb-2")
            ),
            shiny::column(4L,
              actionButton(ns("card_control_2_close"), "Close",
                           class = "btn-danger btn-sm w-100 mb-2")
            ),
            shiny::column(4L,
              actionButton(ns("card_control_2_toggle"), "Toggle",
                           class = "btn-secondary btn-sm w-100 mb-2")
            )
          ),
          html_highlight_code(
            card2_open("card_control_2"),
            width.cutoff = 20L, hover = "overflow-auto"
          )
        )
      ),
      card2(
        inputId = ns("card_control_2"),
        title = "Card with B-side",
        class_body = "min-height-200",
        body_main = tagList(
          p("Main side."),
          p(
            "Click the ", as_icon("ellipsis-v"),
            " button or use the controls above to open/close the B-side."
          )
        ),
        body_side = tagList(
          h5("Configuration Panel"),
          p(tags$code("card2_open()"), " opens this side."),
          p(tags$code("card2_close()"), " closes this side."),
          p(tags$code("card2_toggle()"), " toggles this side.")
        ),
        tools = list(
          card_tool(widget = "card2-switch")
        )
      )
    ),

    # --- 3. Plain card: no btn-tools, purely server-side controlled ---
    shiny::column(
      width = 4L,
      card(
        title = "Server-only Card Control",
        class_body = "no-padding",
        shiny::div(
          class = "p-3",
          p(
            "The card below has ", tags$strong("no tool buttons"),
            " in its header. All collapse / expand / maximize actions are",
            " triggered from R using ", tags$code("card_operate()"), "."
          ),
          shiny::fluidRow(
            shiny::column(6L,
              actionButton(ns("card_control_3_collapse"), "Collapse",
                           class = "btn-warning btn-sm w-100 mb-2")
            ),
            shiny::column(6L,
              actionButton(ns("card_control_3_expand"), "Expand",
                           class = "btn-success btn-sm w-100 mb-2")
            ),
            shiny::column(6L,
              actionButton(ns("card_control_3_maximize"), "Maximize",
                           class = "btn-primary btn-sm w-100")
            ),
            shiny::column(6L,
              actionButton(ns("card_control_3_minimize"), "Minimize",
                           class = "btn-secondary btn-sm w-100")
            )
          ),
          html_highlight_code(
            {
              # No tools needed on the card — server controls it directly
              card_operate("card_control_3", method = "collapse")
              card_operate("card_control_3", method = "expand")
              card_operate("card_control_3", method = "maximize")
              card_operate("card_control_3", method = "minimize")
            },
            width.cutoff = 20L, hover = "overflow-auto"
          )
        )
      ),
      card(
        title = "Controlled Card (No Tools)",
        # inputId enables card_operate() to find this card
        inputId = ns("card_control_3"),
        class_body = "min-height-200",
        # No `tools` argument — this is the key demonstration
        p("This card has no tool buttons."),
        p(
          "Collapse, expand, and maximize are driven entirely from the observer ",
          "in server.R via ", tags$code("card_operate()"), "."
        ),
        p(style = "color: var(--bs-secondary);",
          "Try the buttons in the control card above.")
      )
    )

  )
}
