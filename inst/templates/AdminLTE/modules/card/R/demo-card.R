
verbatim <- function(code){
  tags$code(
    class='clipboard-btn shinytemplates-clipboard-output',
    'data-clipboard-text'=code,
    role='button', title='Click to copy!',
    code)
}

ui_card_controls <- function(){

  tagList(
    column(
      width = 4L,
      card(
        inputId = ns("card_control_3"),
        title = "Card Expand",
        class_foot = "display-block-force",
        body_main = div(
          p(
            class = 'inline-all',
            "Use ",
            verbatim("card_operate(...)"),
            " to collapse, expand, maximize, or minimize",
            tags$code("card"), ", ",
            tags$code("card2"), ", ",
            tags$code("card_tabset"), ". Even without card tools."
          )
        ),
        footer = tagList(
          fluidRow(
            column(width = 6L, actionButton(ns("card_control_3_collapse"), "Collapse", width = "100%")),
            column(width = 6L, actionButton(ns("card_control_3_expand"), "Expand", width = "100%"))),
          div(class = "space-vertical-5"),
          fluidRow(
            column(width = 6L, actionButton(ns("card_control_3_maximize"), "Maximize", width = "100%")),
            column(width = 6L, actionButton(ns("card_control_3_minimize"), "Minimize", width = "100%"))
          )
        )
      )
    ),
    column(
      width = 4L,
      card_tabset(
        inputId = ns("card_control_1"),
        title = "Cardset",
        active = "Tab B",
        class_body = "no-padding min-height-50",
        "Tab A" = html_highlight_code(
          card_tabset_activate(inputId = "card_control_1",
                               title = "Tab A"),
          args.newline = FALSE, copy_on_click = TRUE,
          hover = "overflow-auto", width.cutoff = 20L
        ),
        "Tab B" = div(
          class = "padding-20",
          p(
            class = "inline-all",
            "By specifying ", span(
              tags$code('active="Tab B"')
            ), ", this tab is activated by default."
          )
        ),
        footer = fluidRow(
          column(
            width = 6L,
            actionButton(ns('switch_tab_a'), "Switch to Tab A", width = "100%")
          ),
          column(
            width = 6L,
            actionButton(ns('add_tab_a'), "New Tab", width = "100%")
          )
        )
      )
    ),
    column(
      width = 4L,
      card2(
        inputId = ns("card_control_2"),
        title = "Card2",
        class_body = "min-height-100",
        body_main = div(
          class = "padding-20",
          p(
            class = 'inline-all',
            verbatim("card2_open(...)"), ", ",
            verbatim("card2_close(...)"), ", ",
            verbatim("card2_toggle(...)"), "."
          )
        ),
        body_side = p("Card - side B"),
        footer = fluidRow(
          column(width = 4L, actionButton(ns("card_control_2_open"), "Open B-side", width = "100%")),
          column(width = 4L, actionButton(ns("card_control_2_close"), "Close B-side", width = "100%")),
          column(width = 4L, actionButton(ns("card_control_2_toggle"), "Toggle B-side", width = "100%"))
        )
      )
    )
  )

}
