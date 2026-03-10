library(shiny)
library(shidashi)

# ===========================================================================
# QUICK START SECTION
# ===========================================================================

ui_quick_start <- function() {
  fluidRow(
    column(
      width = 12L,
      h3("Quick Start", class = "shidashi-anchor"),
      tags$div(
        class = "alert alert-info",
        tags$strong("2-Minute Setup: "),
        "Run one command in R, paste config into VS Code, done!"
      )
    ),
    column(
      width = 6L,
      card(
        title = "1. Run in R Console",
        tags$pre(
          class = "bg-gray-90 pre-compact",
          tags$code(
            class = "r",
            "shidashi:::setup_mcp_proxy()"
          )
        ),
        tags$p(
          class = "mb-0",
          "This prints a JSON config — copy it!"
        )
      )
    ),
    column(
      width = 6L,
      card(
        title = "2. Paste into VS Code",
        tags$p(
          "Create ", tags$code(".vscode/mcp.json"), " and paste the config."
        ),
        tags$p(
          class = "mb-0",
          "Restart VS Code. The shidashi MCP server is now available!"
        )
      )
    ),
    column(
      width = 12L,
      card(
        title = "3. Test It",
        tags$ol(
          class = "mb-0",
          tags$li("Start your shidashi app: ", tags$code("shidashi::render()")),
          tags$li("Open a module page in your browser"),
          tags$li(
            "In VS Code Copilot Chat, ask: ",
            tags$em("\"Use the hello_world tool to greet me\"")
          )
        )
      )
    )
  )
}


# ===========================================================================
# DETAILS SECTION (For those who want more info)
# ===========================================================================

ui_details <- function() {
  fluidRow(
    column(
      width = 12L,
      h3("Details", class = "shidashi-anchor"),
      p("Expand sections below for more configuration options.")
    ),
    column(
      width = 12L,
      accordion(
        id = ns("details_accordion"),

        # --- Architecture ---
        accordion_item(
          title = "How It Works",
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
'VS Code/Claude Code    (MCP Client)
       |
       | stdio (JSON-RPC)
       v
  mcp-proxy.mjs        (Node.js proxy)
       |
       | HTTP
       v
  Shiny /mcp           (Your app)'
            )
          ),
          tags$p(
            "The proxy translates stdio into HTTP. ",
            "It auto-discovers the active Shiny port from cached records."
          )
        ),

        # --- VS Code config ---
        accordion_item(
          title = "VS Code Configuration",
          tags$p(
            "Create ", tags$code(".vscode/mcp.json"), " with the path from ",
            tags$code("setup_mcp_proxy()"), ":"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "json",
'// .vscode/mcp.json
{
  "servers": {
    "shidashi": {
      "type": "stdio",
      "command": "node",
      "args": ["<PROXY_PATH>"]
    }
  }
}'
            )
          ),
          tags$p(
            "To target a specific port: ",
            tags$code('"args": ["<PROXY_PATH>", "8310"]')
          )
        ),

        # --- Claude Code config ---
        accordion_item(
          title = "Claude Code Configuration",
          tags$p(
            "Create ", tags$code(".mcp.json"), " in your project root:"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "json",
'// .mcp.json
{
  "mcpServers": {
    "shidashi": {
      "command": "node",
      "args": ["<PROXY_PATH>"]
    }
  }
}'
            )
          ),
          tags$p("Or use ", tags$code("~/.claude/mcp.json"), " for global config.")
        ),

        # --- Find proxy path ---
        accordion_item(
          title = "Finding the Proxy Path",
          tags$p(
            "The path is platform-specific. Use R to find it:"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "r",
'# Method 1: setup_mcp_proxy() prints and returns the path
proxy_path <- shidashi:::setup_mcp_proxy()

# Method 2: compute it directly
proxy_path <- file.path(
  tools::R_user_dir("shidashi", "cache"),
  "mcp_server", "mcp-proxy.mjs"
)'
            )
          )
        ),

        # --- Troubleshooting ---
        accordion_item(
          title = "Troubleshooting",
          tags$dl(
            tags$dt("\"No tools available\""),
            tags$dd("Open a module page first. The Shiny session must be active."),

            tags$dt("\"Connection refused\""),
            tags$dd(
              "The Shiny app isn't running. Start it with ",
              tags$code("shidashi::render()"), "."
            ),

            tags$dt("Tools appear but calls fail"),
            tags$dd(
              "Make sure the agent is in ", tags$strong("Executing"), " mode ",
              "and bound to a session."
            ),

            tags$dt("Proxy not found"),
            tags$dd(
              "Run ", tags$code("shidashi:::setup_mcp_proxy()"),
              " again in R."
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

server_mcpsetup <- function(input, output, session, ...) {
  # No server logic needed for this documentation module
}
