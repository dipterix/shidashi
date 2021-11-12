library(shiny)
library(shidashi)
library(ggplot2)
library(ggExtra)
library(plyr)

ui_demo_summary <- function(){
  fluidRow(

    column(
      width = 3L,
      info_box(
        icon = "cog",
        span(class = "info-box-text", "Memory Usage"),
        span(class = "info-box-number", "324 MB")
      )
    ),
    column(
      width = 3L,
      info_box(
        icon = "thumbs-up",
        span(class = "info-box-text", "Likes"),
        span(class = "info-box-number", "12,320"),
        class_icon = "bg-red"
      )
    ),
    column(
      width = 3L,
      info_box(
        icon = "shopping-cart",
        span(class = "info-box-text", "Sales"),
        span(class = "info-box-number", "1,829"),
        class_icon = "bg-success"
      )
    ),
    column(
      width = 3L,
      info_box(
        icon = "users",
        span(class = "info-box-text", "Users"),
        span(class = "info-box-number", "1,290"),
        class_icon = "bg-yellow"
      )
    )
  )
}

ui_demo_monthly <- function(){
  fluidRow(

    column(
      width = 9L,
      div(class = "shidashi-anchor max-height-0 visibility-none", "Sales Report"),
      card(
        title = "Sales Report",
        class_body = "height-300",
        resizable = TRUE,
        tools = list(
          as_badge(sprintf("%s|bg-primary", Sys.Date())),
          card_tool(widget = "flip", title = "See details"),
          card_tool(widget = 'collapse'),
          card_tool(widget = 'link', href = "https://github.com/dipterix/shidashi"),
          card_tool(widget = 'maximize')
        ),
        flip_box(
          class = "fill",
          front = plotOutput(ns("sales_report"), height = "100%"),
          back = shiny::tableOutput(ns("sales_table"))
        ),
        footer = fluidRow(
          column(
            width = 4L,
            div(
              class = "description-block border-right",
              span(
                class = "description-percentage text-success",
                as_icon("caret-up"), "17%"
              ),
              h5(
                class = "description-header",
                "$35,210.43"
              ),
              span(
                class = "description-text",
                "TOTAL REVENUE"
              )
            )
          ),
          column(
            width = 4L,
            div(
              class = "description-block border-right",
              span(
                class = "description-percentage text-warning",
                as_icon("caret-left"), "0%"
              ),
              h5(
                class = "description-header",
                "$10,390.90"
              ),
              span(
                class = "description-text",
                "TOTAL COST"
              )
            )
          ),
          column(
            width = 4L,
            div(
              class = "description-block",
              span(
                class = "description-percentage text-success",
                as_icon("caret-up"), "10%"
              ),
              h5(
                class = "description-header",
                "$14,123.90"
              ),
              span(
                class = "description-text",
                "TOTAL PROFIT"
              )
            )
          )


        )
      )
    ),
    column(
      width = 3L,
      card(
        title = "Goal Completion",
        class_body = "height-300",
        tools = list(
          card_tool(widget = 'collapse')
        ),
        footer = fluidRow(
          column(
            width = 12L,
            div(
              class = "description-block",
              span(
                class = "description-percentage text-danger",
                as_icon("caret-down"), "30%"
              ),
              h5(
                class = "description-header",
                "1163"
              ),
              span(
                class = "description-text",
                "GOAL COMPLETIONS"
              )
            )
          )
        ),
        column(
          width = 12L,
          h6(class = "text-center", "Goal Completion"),
          progressOutput(ns("sales_report_prog1"), description = "",
                         "Add Products to Cart",
                         span(class="float-right", "123/150"),
                         value = 123/150 * 100),
          progressOutput(ns("sales_report_prog2"), description = "",
                         "Complete Purchase",
                         class = "bg-red",
                         span(class="float-right", "310/400"),
                         value = 310/400 * 100),
          progressOutput(ns("sales_report_prog3"), description = "",
                         "Visit Premium Page",
                         class = "bg-success",
                         span(class="float-right", "480/800"),
                         value = 480/800 * 100),
          progressOutput(ns("sales_report_prog4"), description = "",
                         "Inquiries",
                         class = "bg-yellow",
                         span(class="float-right", "250/500"),
                         value = 250/500 * 100)
        )
      )
    )

  )
}

ui_demo_details <- function(){
  fluidRow(
    column(
      width = 4L,
      card2(
        title = "Scatter plot",
        class_body = "no-padding",
        body_main = flip_box(
          front = div(
            class = "fill-width height-450 min-height-450 resize-vertical",
            plotOutput(ns("iris_plot"), height = "100%")
          ),
          back = tableOutput(ns("iris_plot_data"))
        ),
        body_side = div(
          class = "padding-top-50",
          sliderInput(ns("iris_threshold"),
                      label = "Threshold by Petal.Width",
                      min = 0, max = 3, value = 0, step = 0.1)
        )
      )
    ),
    column(
      width = 8L,
      div(class = "shidashi-anchor max-height-0 visibility-none", "Analysis"),
      card_tabset(
        title = "Analysis",
        class_body = "fill flex-container no-padding min-height-450",
        tools = list(
          card_tool(widget = "custom", icon = "sync", inputId = ns("refresh"), title = "Genearte analysis"),
          card_tool(widget = "maximize")
        ),
        "Histogram" = div(
          class = "fill position-absolute",
          plotOutput(ns("distibution_plot"), height = "100%")
        ),
        "Summary" = div(
          class = "fill position-absolute overflow-auto",
          tableOutput(ns('summary_table'))
        )
      )

    )
  )
}

server_demo <- function(input, output, session, ...){

  event_data <- register_session_events(session)
  local_data <- reactiveValues()

  output$sales_report <- renderPlot({
    theme <- get_theme(event_data)
    list2env(list(session = session), envir=.GlobalEnv)
    par(bg = theme$background, fg = theme$foreground,
        col.lab = theme$foreground, col.main = theme$foreground,
        col.axis = theme$foreground,
        las = 1)
    data("AirPassengers")
    y <- as.vector(t(AirPassengers))
    x <- seq(1, 12, length.out = length(y))
    plot(x, y, axes = FALSE, type = "l",
         xlab = "Time", ylab = "", main = "Sales (1 year)")
    axis(1, at = 1:12, labels = c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"))
    axis(2, seq(100, 600, 250))
  })

  output$sales_table <- renderTable({
    data("airquality")
    head(airquality)
    names(airquality) <- c("Department", "# Transactions", "Revenue (x$1000)",
                           "Returned", "Month", "Day")
    airquality
  }, hover = TRUE, spacing = "s", width = "100%")


  output$iris_plot_data <- renderTable({
    data(iris)
    iris[iris$Petal.Width > input$iris_threshold,
         c("Petal.Length", "Petal.Width", "Species")]
  }, striped = TRUE, spacing = 's', width = '100%')

  generate_ggtheme <- function(
    theme,
    panel.background = element_rect(
      fill = theme$background, color = theme$background),
    plot.background = element_rect(
      fill = theme$background, color = theme$background),
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    axis.line.x.bottom = element_line(color = theme$foreground),
    axis.line.y.left = element_line(color = theme$foreground),
    legend.key = element_rect(fill = theme$background, colour = theme$background),
    rect = element_rect(fill = theme$background, colour = theme$foreground),
    title = element_text(color = theme$foreground),
    text = element_text(color = theme$foreground),
    line = element_line(color = theme$foreground),
    ...){
    ggplot2::theme(
      panel.background = panel.background,
      plot.background = plot.background,
      panel.grid.major = panel.grid.major,
      panel.grid.minor = panel.grid.minor,
      axis.line.x.bottom = axis.line.x.bottom,
      axis.line.y.left = axis.line.y.left,
      legend.key = legend.key,
      rect = rect,
      title = title,
      text = text,
      line = line,
      ...
    )
  }

  output$iris_plot <- renderPlot({
    data(iris)
    theme <- get_theme(event_data)
    ggtheme <- generate_ggtheme(theme)

    iris <- iris[iris$Petal.Width > input$iris_threshold, ]

    validate(
      need(nrow(iris) > 0, "No data point selected")
    )

    ggplot(data=iris) +
      aes(x=Sepal.Length, y=Petal.Length, color=Species) +
      geom_point() +
      geom_rug(col="steelblue",alpha=0.1, size=1.5) + ggtheme
  })


  observeEvent(input$refresh, {
    show_notification(
      title = "Generating analysis...",
      subtitle = "This might take a while",
      class = "bg-primary",
      close = FALSE,
      autohide = FALSE,
      progressOutput(ns("data_gen_pro"), description = "Loading data...",
                     size = 'xs', class = "bg-yellow")
    )
    on.exit({ clear_notifications() })

    progress <- shiny_progress("", max = 10, outputId = "data_gen_pro")
    for(i in 1:10){
      progress$inc(sprintf("step %s", i), message = ifelse(
        i > 5, "Analyze data", "Loading data"
      ))
      Sys.sleep(0.2)
    }
    local_data$data <- data.frame(
      name=c( rep("A",500), rep("B",500), rep("B",500), rep("C",20), rep('D', 100) ,
              sample(LETTERS, 20000, replace = TRUE)),
      value=c( rnorm(500, 10, 5), rnorm(500, 13, 1), rnorm(500, 18, 1), rnorm(20, 25, 4), rnorm(100, 12, 1), rnorm(20000, 15, 30) )
    )
  })
  output$distibution_plot <- renderPlot({
    validate(
      need(is.data.frame(local_data$data), "Please press the refresh button on the top-right tool bar")
    )
    theme <- get_theme(event_data)

    data <- local_data$data
    # sample size
    sample_size <- do.call("rbind", lapply(split(data, data$name), function(x){
      data.frame(
        name = x$name[[1]],
        num = nrow(x)
      )
    }))
    merged <- merge(data, sample_size, by = "name", all.x = TRUE, all.y = FALSE)
    merged$myaxis <- factor(paste0(merged$name, "\n", "n=", merged$num))

    # Plot
    ggtheme <- generate_ggtheme(
      theme, legend.position="none",
      axis.line.y.left = element_blank(),
      axis.text = element_text(color = theme$foreground)
    )
    ggplot(merged) +
      aes(myaxis, value, fill=name) +
      geom_violin(width=1) +
      geom_boxplot(width=0.1, color="grey", alpha=0.2) +
      geom_jitter(height = 0, width = 0.1, size = 0.1, alpha = 0.2) +
      # scale_fill_viridis(discrete = TRUE) +
      # theme_ipsum() +
      ggtheme +
      xlab("")
  })
  output$summary_table <- renderTable({
    validate(
      need(is.data.frame(local_data$data), "Please press the refresh button on the top-right tool bar")
    )
    data <- local_data$data
    # sample size
    sample_size <- do.call("rbind", lapply(split(data, data$name), function(x){
      data.frame(
        name = x$name[[1]],
        num = nrow(x)
      )
    }))
    sample_size
  })
}
