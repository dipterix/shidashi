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
              "This is the front side. Click me"
            )
          ),
          back = info_box(
            icon = NULL,
            p("This is the back side. Click me to toggle back.")
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
              "This is the front side. Click me"
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
