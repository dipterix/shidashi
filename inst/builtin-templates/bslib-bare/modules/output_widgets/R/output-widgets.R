library(shiny)
library(shidashi)

# ---- Base R plot ----

ui_base_plot <- function() {
  column(
    width = 6L,
    card(
      title = "Base R Plot",
      class_body = "min-height-450",
      tools = list(
        card_tool(widget = "maximize")
      ),
      plotOutput(ns("base_plot"), height = "400px")
    )
  )
}

server_base_plot <- function(input, output, session, ...) {
  shidashi::register_session(session)

  register_output(
    renderPlot({
      theme <- shidashi::get_theme()
      par(
        bg = theme$background, fg = theme$foreground,
        col.lab = theme$foreground, col.main = theme$foreground,
        col.axis = theme$foreground
      )
      x <- seq(0, 4 * pi, length.out = 200)
      plot(x, sin(x), type = "l", lwd = 2,
           col = "steelblue", main = "Sine Wave",
           xlab = "x", ylab = "sin(x)")
      lines(x, cos(x), col = "coral", lwd = 2)
      legend("topright",
             legend = c("sin", "cos"),
             col = c("steelblue", "coral"),
             lwd = 2, bg = theme$background,
             text.col = theme$foreground)
    }),
    outputId = "base_plot",
    description = "Sine and cosine wave plot (base R graphics)",
    download_type = "image"
  )
}

# ---- ggplot with brush ----

ui_ggplot_brush <- function() {
  column(
    width = 6L,
    card(
      title = "ggplot2 with Brush",
      class_body = "min-height-450",
      tools = list(
        card_tool(widget = "maximize")
      ),
      plotOutput(ns("gg_brush_plot"), height = "350px",
                 brush = brushOpts(id = ns("gg_brush"))),
      hr(),
      h5("Brushed Points"),
      verbatimTextOutput(ns("brush_info"))
    )
  )
}

server_ggplot_brush <- function(input, output, session, ...) {
  shidashi::register_session(session)

  register_output(
    renderPlot({
      theme <- shidashi::get_theme()
      ggtheme <- ggplot2::theme(
        panel.background = ggplot2::element_rect(
          fill = theme$background, color = theme$background),
        plot.background = ggplot2::element_rect(
          fill = theme$background, color = theme$background),
        panel.grid.major = ggplot2::element_blank(),
        panel.grid.minor = ggplot2::element_blank(),
        axis.line.x.bottom = ggplot2::element_line(color = theme$foreground),
        axis.line.y.left = ggplot2::element_line(color = theme$foreground),
        legend.key = ggplot2::element_rect(
          fill = theme$background, colour = theme$background),
        rect = ggplot2::element_rect(
          fill = theme$background, colour = theme$foreground),
        title = ggplot2::element_text(color = theme$foreground),
        text = ggplot2::element_text(color = theme$foreground),
        line = ggplot2::element_line(color = theme$foreground)
      )

      ggplot2::ggplot(datasets::mtcars,
                      ggplot2::aes(x = wt, y = mpg, color = factor(cyl))) +
        ggplot2::geom_point(size = 3) +
        ggplot2::labs(
          title = "Motor Trend Cars",
          x = "Weight (1000 lbs)",
          y = "Miles per Gallon",
          color = "Cylinders"
        ) + ggtheme
    }),
    outputId = "gg_brush_plot",
    description = "ggplot scatter of mtcars (wt vs mpg) with brush selection",
    output_opts = list(brush = brushOpts(id = ns("gg_brush"))),
    download_type = "image"
  )

  output$brush_info <- renderPrint({
    brush <- input$gg_brush
    if (is.null(brush)) {
      cat("Drag to select points on the plot above.\n")
    } else {
      pts <- brushedPoints(datasets::mtcars, brush,
                           xvar = "wt", yvar = "mpg")
      if (nrow(pts) == 0L) {
        cat("No points selected.\n")
      } else {
        print(pts[, c("mpg", "cyl", "wt", "hp")])
      }
    }
  })
}

# ---- threeBrain viewer ----

ui_threebrain <- function() {
  column(
    width = 12L,
    card(
      title = "threeBrain 3D Viewer",
      class_body = "min-height-450",
      tools = list(
        card_tool(widget = "maximize")
      ),
      threebrain_output_ui(ns("brain_viewer"), height = "500px"),
      hr(),
      h5("Double-click Event"),
      verbatimTextOutput(ns("brain_click_info"))
    )
  )
}

threebrain_output_ui <- function(outputId, height = "500px") {
  if (!requireNamespace("threeBrain", quietly = TRUE)) {
    return(shiny::div(
      class = "alert alert-warning",
      shiny::h4("threeBrain not installed"),
      shiny::p("Install with: ",
               shiny::code('install.packages("threeBrain")'))
    ))
  }
  threeBrain::threejsBrainOutput(outputId, height = height)
}

server_threebrain <- function(input, output, session, ...) {

  if (!requireNamespace("threeBrain", quietly = TRUE)) {
    output$brain_click_info <- renderPrint({
      cat("Package 'threeBrain' is required but not installed.\n")
    })
    return(invisible())
  }

  b <- threeBrain::merge_brain()
  b$template_object$set_electrodes(data.frame(
    Electrode = 1:10,
    x = stats::rnorm(10) * 20,
    y = stats::rnorm(10) * 20,
    z = stats::rnorm(10) * 20,
    Label = LETTERS[1:10]
  ))

  register_output(
    threeBrain::renderBrain({
      b$plot()
    }),
    outputId = "brain_viewer",
    description = "3D brain viewer with 10 random electrodes",
    download_type = "threeBrain"
  )

  proxy <- threeBrain::brain_proxy("brain_viewer")

  output$brain_click_info <- renderPrint({
    event <- proxy$mouse_event_double_click
    if (is.null(event)) {
      cat("Double-click an electrode in the 3D viewer.\n")
    } else {
      str(event)
    }
  })
}
