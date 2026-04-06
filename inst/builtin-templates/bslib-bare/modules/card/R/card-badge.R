
ui_card_badge <- function() {
  tagList(

    # --- 1. Static badge in card header ---
    shiny::column(
      width = 4L,
      card(
        title = "Static Badge",
        class_body = "no-padding",
        tools = list(
          card_badge("Ready", class = "bg-success shidashi-output-status")
        ),
        shiny::div(
          class = "p-3",
          p(
            tags$code("card_badge()"), " places a badge in the card header. ",
            "It is more flexible than ", tags$code("as_badge()"), " because ",
            "it can be updated from the server at runtime."
          ),
          html_highlight_code(
            card(
              title = "My Card",
              tools = list(
                card_badge("Ready",
                           class = "bg-success shidashi-output-status")
              )
            ),
            width.cutoff = 20L, hover = "overflow-auto"
          )
        )
      )
    ),

    # --- 2. Dynamic badge updated from the server ---
    shiny::column(
      width = 4L,
      card(
        title = "Dynamic Badge",
        class_body = "no-padding",
        tools = list(
          card_badge(
            text = "Up-to-date",
            class = "bg-success shidashi-output-status",
            id = ns("badge_status_demo")
          )
        ),
        shiny::div(
          class = "p-3",
          p(
            "Use ", tags$code("set_card_badge()"), " on the server to change ",
            "the badge text, add, or remove CSS classes dynamically."
          ),
          shiny::fluidRow(
            shiny::column(6L,
              actionButton(
                ns("badge_set_refresh"),
                "Need Refresh",
                class = "btn-warning btn-sm w-100 mb-2"
              )
            ),
            shiny::column(6L,
              actionButton(
                ns("badge_set_ready"),
                "Up-to-date",
                class = "btn-success btn-sm w-100 mb-2"
              )
            )
          ),
          html_highlight_code(
            {
              # Use id to target a single badge by namespace
              set_card_badge(
                id = ns("badge_status_demo"),
                text = "Refresh needed",
                add_class = "bg-yellow",
                remove_class = "bg-success"
              )

              # Use class selector to target all badges with that class
              set_card_badge(
                class = "shidashi-output-status",
                text = "Up-to-date",
                add_class = "bg-success",
                remove_class = "bg-yellow"
              )
            },
            width.cutoff = 20L, hover = "overflow-auto"
          )
        )
      )
    ),

    # --- 3. Recalculate badge convenience helpers ---
    shiny::column(
      width = 4L,
      card(
        title = "Recalculate Badge",
        class_body = "no-padding",
        tools = list(
          card_recalculate_badge()
        ),
        shiny::div(
          class = "p-3",
          p(
            tags$code("card_recalculate_badge()"), " is a pre-styled badge ",
            "that acts as a button to trigger re-run. ",
            "Use ", tags$code("enable_recalculate_badge()"), " / ",
            tags$code("disable_recalculate_badge()"),
            " to flip it on/off from the server."
          ),
          shiny::fluidRow(
            shiny::column(6L,
              actionButton(
                ns("badge_enable_recalculate"),
                "Enable",
                class = "btn-warning btn-sm w-100 mb-2"
              )
            ),
            shiny::column(6L,
              actionButton(
                ns("badge_disable_recalculate"),
                "Disable",
                class = "btn-success btn-sm w-100 mb-2"
              )
            )
          ),
          html_highlight_code(
            {
              # Mark output as stale
              enable_recalculate_badge()

              # Mark output as up-to-date
              disable_recalculate_badge()
            },
            width.cutoff = 20L, hover = "overflow-auto"
          )
        )
      )
    )
  )
}
