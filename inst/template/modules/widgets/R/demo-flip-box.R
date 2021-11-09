ui_flip_box <- function(){

  shiny::tagList(
    # Displays Code
    column(
      width = 3L,
      infobox_with_code(
        flip_box(
          front = info_box(
            icon = "bookmark",
            p(
              "This is the front side. Double-click me"
            )
          ),
          back = info_box(
            icon = NULL,
            p("This is the back side. Double-click me to toggle back.")
          )
        )
      )
    ),
    column(
      width = 5L,
      infobox_with_code(
        flip_box(
          active_on = "click-front",
          inputId = ns("flip_demo_2"),
          front = info_box(
            icon = "th",
            p(
              "This is the front side. Double-click me"
            )
          ),
          back = info_box(
            icon = NULL,
            plotOutput(ns("flip_box_plot")),
            p(
              "Click this button and a progress will run. ",
              "Once the progress finishes, the box will flip back. "
            ),
            actionButton(ns("show_progress"), "Show Progress")
          )
        )
      )
    ),
    column(
      width = 4L,
      infobox_with_code(
        flip_box(
          active_on = "manual",
          inputId = ns("flip_demo_3"),
          front = info_box(
            icon = "arrow-right",
            p(
              "This is the front side. Click this button"
            ),
            actionButton(ns("flip_btn_1"), "Flip")
          ),
          back = info_box(
            icon = "arrow-left",
            p(
              "This is the back side. Click this button"
            ),
            actionButton(ns("flip_btn_2"), "Flip again")
          )
        )
      )
    )
  )

}

ui_flip_card <- function(){
  tagList(
    column(
      width = 5L,
      card(
        title = "Card with flip box",
        class_body = "no-padding",
        tools = list(
          card_tool(widget = "flip")
        ),
        flip_box(
          front = div(
            p(
              class = "padding-20",
              "While you can still flip the box by double-clicking, ",
              "alternatively, clicking the 'flip' icon in the tool bar also flips the box."
            ),
            plotOutput(ns("flip_card_plot"))
          ),
          back = div(
            class = "padding-20",
            p("The data used to generate the figure"),
            tableOutput(ns("flip_card_table"))
          )
        )
      )
    )
  )
}
