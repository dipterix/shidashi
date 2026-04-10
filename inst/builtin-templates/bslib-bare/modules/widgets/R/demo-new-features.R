library(shiny)
library(shidashi)

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

ui_new_features <- function() {
  tagList(
    # --- Module info ---
    column(
      width = 12L,
      h4("Current Module Info", class = "shidashi-anchor"),
      p(
        class = "inline-all",
        tags$code("current_module()"), " returns a named list ",
        "with ", tags$code("id"), ", ", tags$code("label"), ", ",
        tags$code("group"), ", ", tags$code("icon"), ", ",
        tags$code("badge"), ", and ", tags$code("url"),
        " for the module that is currently running."
      ),
      verbatimTextOutput(ns("current_module_info"))
    ),

    # --- Drawer ---
    column(
      width = 6L,
      card(
        title = "Drawer",
        class_body = "min-height-200",
        body_main = div(
          p(
            class = "inline-all",
            "Open a right-side panel (drawer) from R. ",
            "You can also click the ",
            as_icon("cog"),
            " icon in the navbar. ",
            "Works from within modules (cross-iframe)."
          ),
          html_highlight_code(
            {
              drawer_open()
              drawer_close()
              drawer_toggle()
            },
            width.cutoff = 20L, hover = "overflow-auto"
          )
        ),
        footer = fluidRow(
          column(4L, actionButton(ns("drawer_open"), "Open",
                                  class = "btn-primary btn-sm w-100 mb-2")),
          column(4L, actionButton(ns("drawer_close"), "Close",
                                  class = "btn-danger btn-sm w-100 mb-2")),
          column(4L, actionButton(ns("drawer_toggle"), "Toggle",
                                  class = "btn-secondary btn-sm w-100 mb-2"))
        )
      )
    ),

    # --- open_url ---
    column(
      width = 6L,
      card(
        title = "Open URL",
        class_body = "min-height-200",
        body_main = div(
          p(
            class = "inline-all",
            "Open a URL in the browser from R. ",
            "Accepts any valid URL."
          ),
          html_highlight_code(
            open_url("https://github.com/dipterix/shidashi"),
            width.cutoff = 25L, hover = "overflow-auto"
          )
        ),
        footer = fluidRow(
          column(6L, actionButton(ns("open_url_github"), "GitHub Page",
                                  class = "btn-info btn-sm w-100 mb-2")),
          column(6L, actionButton(ns("open_url_cran"), "CRAN Link",
                                  class = "btn-outline-secondary btn-sm w-100 mb-2"))
        )
      )
    ),

    # --- Resizable card demo ---
    column(
      width = 6L,
      card(
        title = "Resize Handles",
        class_body = "height-300 resize-vertical",
        tools = list(
          card_tool(widget = "maximize")
        ),
        body_main = div(
          p(
            class = "inline-all",
            "Add ", tags$code('class_body = "resize-vertical"'),
            " to make the card body vertically resizable. ",
            "Drag the bottom handle to resize."
          ),
          html_highlight_code(
            card(
              title = "Resizable Card",
              class_body = "height-300 resize-vertical",
              plotOutput(ns("plot"), height = "100%")
            ),
            width.cutoff = 20L, hover = "overflow-auto"
          ),
          plotOutput(ns("resize_demo_plot"), height = "120px")
        )
      )
    ),

    # --- Horizontal resize panel
    column(
      width = 6L,
      card(
        title = "Horizontal Resize (split pane)",
        class_body = "height-300",
        tools = list(
          card_tool(widget = "maximize")
        ),
        body_main = div(
          style = "display:flex;height:100%;",
          div(
            style = "flex:1; padding: 0.5rem; overflow:auto;",
            p("Left pane"),
            p("Drag the divider to resize.")
          ),
          div(class = "resize-horizontal"),
          div(
            style = "flex:1; padding: 0.5rem; overflow:auto;",
            p("Right pane"),
            p("Add class ",
              tags$code("resize-horizontal"),
              " to a divider element."),
            plotOutput(ns("resize_demo_plot2"), height = "120px",
                       width = "100%")
          )
        )
      )
    )
  )
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server_new_features <- function(input, output, session, ...) {

  # Current module info
  output$current_module_info <- renderPrint({
    info <- current_module()
    utils::str(info)
  })

  # Drawer controls
  observeEvent(input$drawer_open, {
    drawer_open()
  })
  observeEvent(input$drawer_close, {
    drawer_close()
  })
  observeEvent(input$drawer_toggle, {
    drawer_toggle()
  })

  # open_url controls
  observeEvent(input$open_url_github, {
    open_url("https://github.com/dipterix/shidashi")
  })
  observeEvent(input$open_url_cran, {
    open_url("https://cran.r-project.org/package=shidashi")
  })

  # Demo plot for resizable card
  output$resize_demo_plot <- renderPlot({
    par(mar = c(2, 2, 1, 1))
    plot(cars, pch = 19, col = "steelblue", main = "Resize me!")
    abline(lm(dist ~ speed, data = cars), col = "tomato", lwd = 2)
  })

  output$resize_demo_plot2 <- renderPlot({
    par(mar = c(2, 2, 1, 1))
    plot(cars, pch = 19, col = "steelblue", main = "Resize me!")
    abline(lm(dist ~ speed, data = cars), col = "tomato", lwd = 2)
  })
}
