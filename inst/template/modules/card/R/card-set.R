
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
        "Tab 1" = p("Tab content 1")
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
                if(input$add_card %% 2) {
                  card_tabset_insert(
                    inputId = "card_tabset_expand_demo",
                    title = "More...",
                    p("...")
                  )
                } else {
                  card_tabset_remove(
                    inputId = "card_tabset_expand_demo",
                    title = "More..."
                  )
                }

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
