library(shiny)
library(shidashi)

# ===========================================================================
# QUICK START SECTION (What users see first)
# ===========================================================================

ui_quick_start <- function() {
  fluidRow(
    column(
      width = 12L,
      h3("Quick Start", class = "shidashi-anchor"),
      tags$div(
        class = "alert alert-info",
        tags$strong("30-Second Setup: "),
        "Click the ", as_icon("robot"), " button in the bottom-right → ",
        "Type a prompt → Done!"
      )
    ),
    column(
      width = 4L,
      card(
        title = "1. Open the Chatbot",
        tags$p(
          "Click ",
          tags$a(
            href = "#",
            class = "btn btn-sm btn-primary",
            `data-shidashi-action` = "drawer-toggle",
            as_icon("robot"), " Open"
          ),
          " or the ", as_icon("robot"), " button at bottom-right."
        )
      )
    ),
    column(
      width = 4L,
      card(
        title = "2. Choose a Mode",
        tags$ul(
          class = "mb-0",
          tags$li(tags$strong("Ask"), " — Q&A only"),
          tags$li(tags$strong("Plan"), " — Can read data"),
          tags$li(tags$strong("Executing"), " — Can change inputs")
        )
      )
    ),
    column(
      width = 4L,
      card(
        title = "3. Try These Prompts",
        tags$ul(
          class = "mb-0",
          tags$li(tags$em("\"What inputs are here?\"")),
          tags$li(tags$em("\"Change color to purple\"")),
          tags$li(tags$em("\"Set points to 300\""))
        )
      )
    )
  )
}


# ===========================================================================
# LIVE DEMO SECTION (Interactive playground)
# ===========================================================================

ui_live_demo <- function() {
  fluidRow(
    column(
      width = 12L,
      h3("Try It Now", class = "shidashi-anchor"),
      p("These controls are registered with the AI agent. Open the chatbot and ask it to change them!")
    ),
    column(
      width = 4L,
      card(
        title = "Controls",
        shidashi::register_input(
          inputId = "live_npoints",
          description = "Number of random points to plot (10-500)",
          update = "shiny::updateSliderInput",
          expr = sliderInput(
            inputId = ns("live_npoints"),
            label = "Number of points",
            min = 10, max = 500, value = 100, step = 10
          )
        ),
        shidashi::register_input(
          inputId = "live_color",
          description = "Color of the scatter plot points",
          update = "shiny::updateSelectInput(value=selected)",
          expr = selectInput(
            inputId = ns("live_color"),
            label = "Point color",
            choices = c("steelblue", "tomato", "forestgreen",
                        "orange", "purple"),
            selected = "steelblue"
          )
        ),
        shidashi::register_input(
          inputId = "live_title",
          description = "Title displayed above the scatter plot",
          update = "shiny::updateTextInput",
          expr = textInput(
            inputId = ns("live_title"),
            label = "Plot title",
            value = "Agent-Controlled Scatter Plot"
          )
        )
      )
    ),
    column(
      width = 8L,
      card(
        title = "Output",
        tools = list(card_tool(widget = "maximize")),
        class_body = "min-height-400",
        shidashi::register_output(
          outputId = "live_scatter",
          description = "Scatter plot controlled by live_npoints, live_color, and live_title",
          expr = plotOutput(ns("live_scatter"), height = "350px")
        )
      )
    )
  )
}


# ===========================================================================
# DEVELOPER GUIDE (Collapsible details for those who want to learn more)
# ===========================================================================

ui_developer_guide <- function() {
  fluidRow(
    column(
      width = 12L,
      h3("Developer Guide", class = "shidashi-anchor"),
      p("Expand the sections below to learn how to build agent-powered modules.")
    ),

    # --- Section: Register Inputs ---
    column(
      width = 12L,
      accordion(
        id = ns("dev_accordion"),
        accordion_item(
          title = "Register Inputs (shidashi::register_input)",
          tags$p(
            "Wrap any Shiny input with ", tags$code("register_input()"),
            " to make it visible to AI agents:"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "r",
'shidashi::register_input(
  inputId = "my_slider",
  description = "Adjusts the threshold value (0-100)",
  update = "shiny::updateSliderInput",
  expr = sliderInput(ns("my_slider"), "Threshold", 0, 100, 50)
)'
            )
          ),
          tags$p(
            tags$strong("Parameters:"),
            tags$ul(
              tags$li(tags$code("inputId"), " — Input name (without namespace)"),
              tags$li(tags$code("description"), " — What the agent sees"),
              tags$li(tags$code("update"), " — Function to change the value"),
              tags$li(tags$code("expr"), " — The actual Shiny input widget")
            )
          )
        ),

        # --- Section: Register Outputs ---
        accordion_item(
          title = "Register Outputs (shidashi::register_output)",
          tags$p(
            "Wrap any Shiny output with ", tags$code("register_output()"),
            " to help agents understand what's displayed:"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "r",
'shidashi::register_output(
  outputId = "my_plot",
  description = "Histogram showing data distribution",
  expr = plotOutput(ns("my_plot"))
)'
            )
          )
        ),

        # --- Section: agents.yaml ---
        accordion_item(
          title = "Enable Agent Features (agents.yaml)",
          tags$p(
            "Create ", tags$code("agents.yaml"), " in your module folder:"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "yaml",
'# modules/mymodule/agents.yaml
default_mode: "Executing"
system_prompt: |
  You help users analyze data in this module.

modes:
  Ask:
    tools: []
  Plan:
    tools: [shiny_input_info, shiny_output_info]
  Executing:
    tools: [shiny_input_info, shiny_input_update, shiny_output_info]'
            )
          ),
          tags$p(
            tags$strong("Modes control what the agent can do:"),
            tags$ul(
              tags$li(tags$strong("Ask"), " — No tools, just conversation"),
              tags$li(tags$strong("Plan"), " — Can read inputs/outputs"),
              tags$li(tags$strong("Executing"), " — Can also update inputs")
            )
          )
        ),

        # --- Section: Custom Tools ---
        accordion_item(
          title = "Custom MCP Tools (mcp_wrapper)",
          tags$p(
            "Create custom tools with ", tags$code("mcp_wrapper()"), ":"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "r",
'# In module R/ folder
my_tool <- shidashi::mcp_wrapper(function(session) {
  ellmer::tool(
    name = "calculate_stats",
    description = "Calculate statistics for the current data",
    arguments = list(
      column = ellmer::tool_arg("string", "Column name")
    ),
    fun = function(column) {
      data <- session$userData$current_data
      paste("Mean:", mean(data[[column]], na.rm = TRUE))
    }
  )
})'
            )
          ),
          tags$p(
            "Then add to ", tags$code("agents.yaml"), ": ",
            tags$code("tools: [calculate_stats]")
          )
        ),

        # --- Section: Skills ---
        accordion_item(
          title = "Skills (Script-Based Tools)",
          tags$p(
            "For complex operations, create a skill folder with ",
            tags$code("SKILL.md"), " and scripts:"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
'modules/mymodule/skills/analyze/
├── SKILL.md        # Defines tool name, args, descriptions
└── scripts/
    └── run.R       # The actual script'
            )
          ),
          tags$p("Example ", tags$code("SKILL.md"), ":"),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "yaml",
'---
name: analyze_data
description: Run statistical analysis
arguments:
  - name: method
    type: string
    description: "lm" or "glm"
script: scripts/run.R
---'
            )
          )
        )
      )
    )
  )
}


# ===========================================================================
# SERVER
# ===========================================================================

server_aiagent <- function(input, output, session, ...) {
  event_data <- register_session_events(session)

  output$live_scatter <- renderPlot({
    theme <- shidashi::get_theme(event_data)
    n <- input$live_npoints %||% 100
    col <- input$live_color %||% "steelblue"
    title <- input$live_title %||% "Scatter Plot"

    set.seed(42)
    x <- rnorm(n)
    y <- x + rnorm(n, sd = 0.5)

    par(
      bg = theme$background, fg = theme$foreground,
      col.main = theme$foreground,
      col.axis = theme$foreground,
      col.lab = theme$foreground
    )
    plot(x, y, pch = 19, col = col, main = title,
         xlab = "X", ylab = "Y")
  })
}


# ===========================================================================
# CUSTOM TOOL (for demo)
# ===========================================================================

trigger_refresh <- shidashi::mcp_wrapper(
  function(session) {
    ns <- session$ns
    shared_data <- shidashi::register_session_id(session)
    ellmer::tool(
      fun = function() {
        shared_data$reactives[[ns("refresh")]] <- Sys.time()
        "Refresh triggered."
      },
      name = "trigger_refresh",
      description = "Trigger a refresh action in the AI agent demo module.",
      arguments = list()
    )
  }
)
