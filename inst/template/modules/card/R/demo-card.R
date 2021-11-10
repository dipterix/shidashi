
verbatim <- function(code){
  tags$code(
    class='clipboard-btn shidashi-clipboard-output',
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
            column(width = 6L, actionButton(ns("card_control_3_collapse"), "Collapse")),
            column(width = 6L, actionButton(ns("card_control_3_expand"), "Expand"))),
          div(class = "space-vertical-5"),
          fluidRow(
            column(width = 6L, actionButton(ns("card_control_3_maximize"), "Maximize")),
            column(width = 6L, actionButton(ns("card_control_3_minimize"), "Minimize"))
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
        class_body = "padding-20 min-height-100",
        "Tab A" = div(
          p(
            class = "inline-all",
            "To activate a tab, use ",
            verbatim("card_tabset_activate(...)"), ". ",
            "For example, ",
            verbatim('card_tabset_activate(inputId = "card_control_1", title = "Tab A")')
          )
        ),
        "Tab B" = div(
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
            actionButton(ns('switch_tab_a'), "Switch to Tab A")
          ),
          column(
            width = 6L,
            actionButton(ns('add_tab_a'), "New Tab")
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
            "use ",
            verbatim("card2_open(...)"), ", ",
            verbatim("card2_close(...)"), ", ",
            verbatim("card2_toggle(...)"),
            " to control the B-side from within R."
          )
        ),
        body_side = p("Card - side B"),
        footer = fluidRow(
          column(width = 4L, actionButton(ns("card_control_2_open"), "Open B-side")),
          column(width = 4L, actionButton(ns("card_control_2_close"), "Close B-side")),
          column(width = 4L, actionButton(ns("card_control_2_toggle"), "Toggle B-side"))
        )
      )
    )
  )

}
