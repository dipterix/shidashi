
card_with_code <- function(expr, env = parent.frame(),
                           class = "height-50", width.cutoff = 25L){
  expr <- substitute(expr)
  x <- eval(expr, envir = env)
  code <- show_ui_code(x, class = class, width.cutoff = width.cutoff)
  expr[["class_foot"]] <- "display-block bg-gray-90 no-padding code-display fill-width"
  expr[["footer"]] <- code
  eval(expr, envir = env)
}



ui_card_basic <- function(){

  shiny::tagList(
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Basic Card Example",
        "Card body"
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Primary Card Example 1",
        class = "card-outline card-primary",
        'class = "card-outline card-primary"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Primary Card Example 2",
        class = "card-primary",
        'class = "card-primary"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Primary Card Example 3",
        class = "bg-primary",
        'class = "bg-primary"'
      )
    )),

    # cards with themes
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Secondary Card",
        class = "card-secondary",
        'class = "card-secondary"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Success Card",
        class = "card-success",
        'class = "card-success"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Info Card",
        class = "card-info",
        'class = "card-info"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Warning Card",
        class = "card-warning",
        'class = "card-warning"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Danger Card",
        class = "card-danger",
        'class = "card-danger"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Dark Card",
        class = "card-dark",
        'class = "card-dark"'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Light Card",
        class = "card-light",
        'class = "card-light"'
      )
    ))

  )

}

ui_card_tools <- function(){
  shiny::tagList(
    shiny::column( width = 3L, card_with_code(
      card(
        class_body = "min-height-400",
        title = "Badges",
        tools = list(
          as_badge("New|badge-info"),
          as_badge("3|badge-warning")
        ),
        'Add badges to the top-right corder. ',
        'Use "|" to indicate the badge classes; ',
        'for example: "badge-info", "badge-warning"...'
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Default Tools",
        resizable = TRUE,
        tools = list(
          card_tool(widget = "link", href = "https://github.com/dipterix"),
          card_tool(widget = "refresh"),
          card_tool(widget = "collapse"),
          card_tool(widget = "maximize")
        ),
        # class_body =
        plotOutput(ns("card_defaulttool_plot"), height = "100%")
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Custom Tools",
        class_body = "min-height-400",
        tools = list(
          card_tool(inputId = ns("card_tool_modal"), widget = "custom",
                    title = "Show alert", icon = "bell")
        ),
        'Click the bell icon (', as_icon("bell"),
        ') at the top-right corner to show a pop-up alert', br(),
        "The reaction requires server-side shiny observer. ",
        "Go to 'server.R', add:",
        pre(
          'observeEvent(input$card_tool_modal, {',
          '  shiny::showModal(shiny::modalDialog(',
          '    "Click to dismiss",',
          '    title = "Alert", easyClose = TRUE',
          '  ))',
          '})'
        )
      )
    )),
    shiny::column( width = 3L, card_with_code(
      card(
        title = "Collapsed",
        start_collapsed = TRUE,
        class_body = "min-height-400 no-padding",
        tools = list(
          as_badge("30 messages |badge-primary"),
          card_tool(inputId = ns("card_tool_rerun"), widget = "custom",
                    title = "Re-run", icon = "random"),
          card_tool(widget = "collapse", start_collapsed = TRUE)
        ),
        p(
          style = "padding: 10px; margin: 0;",
          "Click the shuffle (", as_icon("random"), ") button."
        ),
        plotOutput(ns("card_tool_plot"), height = "354px")
      )
    )),
  )
}

ui_card2 <- function(){

  card_ui <- card2(
    title = "Card2 Example",
    class_body = "height-600",
    tools = list(
      card_tool(widget = "link", href = "https://github.com/dipterix"),
      card_tool(widget = "refresh"),
      card_tool(widget = "collapse"),
      card_tool(widget = "maximize")
    ),
    body_main = plotOutput(
      outputId = ns("card2_plot"),
      height = "100%"
    ),
    body_side = flex_container(
      class = "padding-5",
      flex_item(textInput(ns("card2_plot_title"), "Plot title")),
      flex_item(sliderInput(ns("card2_plot_npts"), "# of points", min = 1, max = 100, value = 10, step = 1, round = TRUE))
    )
  )

  shiny::tagList(
    shiny::column( width = 5L, card_ui ),
    shiny::column(
      width = 7L,
      card_tabset(
        class = "min-height-400",
        inputId = ns("card2_code_cardset"),
        "demo-card.R" = fluidRow(
          column(
            width = 12L,
            html_highlight_code(
              get_construct_string(card_ui), quoted = TRUE,
              width.cutoff = 80L, indent = 2, wrap=TRUE,
              args.newline = TRUE, blank = FALSE, copy_on_click = TRUE,
              hover = "overflow-auto"
            )
          )
        ),
        "server.R" = fluidRow(
          column(
            width = 12L,
            html_highlight_code(
              output$card2_plot <- renderPlot({
                npoints <- input$card2_plot_npts
                title <- input$card2_plot_title
                if(!length(title) || title == ''){
                  title <- "Normal Q-Q Plot"
                }
                qqnorm(rnorm(npoints), main = title)
                abline(a = 0, b = 1, col = 'orange3', lty = 2)
              }),
              hover = "overflow-auto"
            )
          )
        )
      )
      #              div(
      # style = "max-height: 450px",
      # html_highlight_code(get_construct_string(card_ui), quoted = TRUE)
    )
  )
}

ui_card_set <- function(){
  tagList(
    shiny::column(
      width = 4L,
      card_tabset(
        class_body = "height-450",
        inputId = ns("card_tabset_demo"),
        title = "House of cards",
        "Code" = flex_container(
          direction = "column",
          flex_item(
            class = "fill-height",
            p("Use key-value pairs to create tab-panels. The keys will be the panel name"),
            html_highlight_code(
              card_tabset(
                title = "House of cards",
                "Tab 1" = p("Tab content 1"),
                "Tab 2" = p("Tab content 2")
              ),
              class = "padding-5 margin-5",
              width.cutoff = 15L,
              hover = "overflow-auto"
            )
          ),
          flex_item(
            class = "fill-height",
            p("Use `names` argument. The length of `names` must be consistent with `...`"),
            html_highlight_code(
              card_tabset(
                title = "House of cards",
                p("Tab content 1"),
                p("Tab content 2"),
                names = c("Tab 1", "Tab 2")
              ),
              class = "padding-5 margin-5 fill",
              width.cutoff = 15L,
              hover = "overflow-auto"
            )
          )
        ),
        "Tab 1" = p("Tab content 1"),
        "Tab 2" = p("Tab content 2")

      )
    ),
    shiny::column(
      width = 4L,
      card_tabset(
        class_body = "height-450",
        inputId = ns("card_tabset_tools_demo"),
        title = "With Tools",
        tools = list(
          as_badge("New|badge-success"),
          card_tool(widget = "collapse"),
          card_tool(widget = "maximize")
        ),
        "Code" = flex_container(
          direction = "column",
          flex_item(
            class = "fill-height",
            html_highlight_code(
              card_tabset(
                title = "Cardset with Tools",
                "Tab 1" = p("Tab content 1"),
                "Tab 2" = p("Tab content 2"),
                class_body = "height-500",
                tools = list(
                  as_badge("New|badge-success"),
                  card_tool(widget = "collapse"),
                  card_tool(widget = "maximize")
                )
              ),
              class = "padding-5 margin-5",
              width.cutoff = 15L,
              hover = "overflow-auto"
            )
          )
        ),
        "Tab 1" = p("Tab content 1"),
        "Tab 2" = p("Tab content 2")

      )
    ),
    shiny::column(
      width = 4L,
      card_tabset(
        class_body = "height-450",
        inputId = ns("card_tabset_expand_demo"),
        title = "Self Expand",
        tools = list(
          card_tool(widget = "custom",
                    icon = shiny::icon("kiwi-bird"),
                    inputId = ns("add_card"))
        ),
        "Code" = flex_container(
          direction = "column",
          flex_item(
            class = "fill-height",
            p("Click on the button to add a new tab!"),
            html_highlight_code(
              card_tabset(
                inputId = ns("card_tabset_expand_demo"),
                title = "Cardset with Tools",
                "server.R" = p("..."),
                class_body = "height-500",
                tools = list(
                  card_tool(widget = "custom",
                            icon = shiny::icon("kiwi-bird"),
                            inputId = ns("add_card"))
                )
              ),
              class = "padding-5 margin-5",
              width.cutoff = 15L,
              hover = "overflow-auto"
            )
          )
        ),
        "server.R" = flex_container(
          direction = "column",
          flex_item(
            class = "fill-height",
            p("An observer listens to click event on `add_card`."),
            html_highlight_code(
              observeEvent(input$add_card, {
                card_tabset_insert(
                  inputId = "card_tabset_expand_demo",
                  title = "More...", active = TRUE,
                  h4("A hidden playground!"),
                  hr(),
                  p("You can use `card_tabset_insert` to ",
                    "insert cards to the cardset. ",
                    "However, if you try to insert a card ",
                    "whose title has already existed, ",
                    "a notification will pop up to warn you.")
                )
              }),
              class = "padding-5 margin-5",
              width.cutoff = 15L,
              hover = "overflow-auto"
            )
          )
        )

      )
    )
  )
}
