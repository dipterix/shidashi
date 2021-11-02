library(shinytemplates)
if(FALSE){
  template_settings$set(
    'root_path' = "inst/templates/AdminLTE/"
  )

  .module_id <- "test"
  ns <- shiny::NS(.module_id)
}

modules <- module_info()

module_title <- function(){
  modules$label[modules$id == .module_id]
}

# Module input panel as accordion

input_panel <- function(){
  accordion(
    id = ns("input-set"),

    accordion_item(
      title = "Input Group A",
      textInput(ns("in1"), "Input 1"),
      collapsed = FALSE,
      footer = "Anim pariatur cliche reprehenderit, enim eiusmod high life accusamus terry richardson ad squid. 3 wolf moon officia aute, non cupidatat skateboard dolor brunch.",
      tools = list(
        as_badge("New|badge-danger")
        # card_tool(widget = "collapse")
      )
    ),


    accordion_item(
      title = "Input Group B",
      textInput(ns("in2"), "Input 2"),
      footer = actionButton("btn1", "OK"),
      collapsed = FALSE,
      tools = list(
        card_tool(widget = "link", icon = shiny::icon("question-circle"),
                  href = "https://rave.wiki")
        # card_tool(widget = "collapse")
      )
    )


  )
}


output_panel <- function(){
  shiny::tagList(
    card2(
      start_collapsed = TRUE,
      title = "Output 1", footer = " bluh bluh bluh...",
      tools = list(
        card_tool(widget = "link",
                  icon = shiny::icon("question-circle"),
                  href = "http://rave.wiki"),
        card_tool(widget = "custom",
                  icon = shiny::icon("tools"),
                  inputId = ns("configure_card")),
        card_tool(widget = "refresh"),
        card_tool(widget = "collapse", start_collapsed = TRUE),
        card_tool(widget = "maximize")
      ),
      # Flex box,
      body_main = "Side A",
      body_side = "Side B"
      # class_body = 'flex-container resize resize-vertical no-padding height-400',
      # flex_item(
      #   class = "fill-height w-100",
      #   shiny::plotOutput(ns("plot"), height = "100%")
      # )
    ),
    card(
      start_collapsed = TRUE,
      title = "Output 1", footer = " bluh bluh bluh...",
      tools = list(
        card_tool(widget = "link",
                  icon = shiny::icon("question-circle"),
                  href = "http://rave.wiki"),
        card_tool(widget = "custom",
                  icon = shiny::icon("tools"),
                  inputId = ns("configure_card")),
        card_tool(widget = "refresh"),
        card_tool(widget = "collapse", start_collapsed = TRUE),
        card_tool(widget = "maximize")
      ),
      # Flex box,
      class_body = 'flex-container resize resize-vertical no-padding height-400',
      flex_item(
        class = "fill-height w-100",
        shiny::plotOutput(ns("plot"), height = "100%")
      )
    ),
    card_tabset(
      inputId = ns("output_tabset"),
      title = 'Output Set',
      "A" = 'asdasd',
      "B" = "asdadadasdasd",
      tools = list(
        card_tool(widget = "link",
                  icon = shiny::icon("question-circle"),
                  href = "http://rave.wiki"),
        card_tool(widget = "custom",
                  icon = shiny::icon("tools"),
                  inputId = ns("add_card")),
        card_tool(widget = "refresh"),
        card_tool(widget = "collapse"),
        card_tool(widget = "maximize")
      )
    )
  )
}
