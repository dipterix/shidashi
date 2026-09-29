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
        "Claude users install the shidashi plugin. For other MCP clients, ",
        "run one command in R and paste the config into VS Code."
      )
    ),
    column(
      width = 12L,
      card(
        title = "Claude Code or Claude Desktop: install the plugin",
        tags$p("In Claude Code, run:"),
        tags$pre(
          class = "bg-gray-90 pre-compact",
          tags$code(
"/plugin marketplace add dipterix/shidashi
/plugin install shidashi@shidashi"
          )
        ),
        tags$p(
          "In Claude Desktop, open ", tags$strong("Customize > Plugins > Add > Add marketplace"),
          ", enter ", tags$code("dipterix/shidashi"), ", then install ",
          tags$strong("shidashi"), "."
        ),
        tags$p(
          class = "mb-0",
          "The plugin needs Node.js 18 or newer. Then skip to ",
          tags$strong("3. Test It"), "."
        )
      )
    ),
    column(
      width = 6L,
      card(
        title = "1. Other clients: run in R Console",
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
          tags$li("Open a module with AI agents (e.g. AI Agent Demo) in your browser"),
          tags$li(
            "In Claude or VS Code Copilot Chat, ask: ",
            tags$em("\"Use the hello_world tool to greet me\"")
          ),
          tags$li(
            "The agent works in the module tab you used last. Click the ",
            as_icon("thumbtack"), " button in a tab to keep the agent there."
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
"VS Code/Claude Code    (MCP Client)
       |
       | stdio (JSON-RPC)
       v
  shidashi proxy       (Node.js; the Claude plugin
       |                or mcp-proxy.mjs in the cache)
       |
       | HTTP
       v
  Shiny /mcp           (Your app)"
            )
          ),
          tags$p(
            "The proxy translates stdio into HTTP. Every running app writes ",
            "a small record (app directory, port, process) to the cache; the ",
            "proxy connects to the most recently started app and stays with ",
            "that app directory, even after the app restarts on a new port."
          ),
          tags$p(
            "The tool list is read from the template on disk, so it is ",
            "available before any browser opens and never changes while the ",
            "agent is connected. No session binding is needed."
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
            "To always drive one app (useful when several apps run at once), ",
            "name its directory: ",
            tags$code('"args": ["<PROXY_PATH>", "--app", "/path/to/app"]')
          ),
          tags$p(
            "To always run tools in one module: ",
            tags$code('"args": ["<PROXY_PATH>", "--module", "demo"]')
          )
        ),

        # --- Which module ---
        accordion_item(
          title = "Which Tab Does the Agent Use?",
          tags$p(
            "Every tool call picks a module tab on its own, in this order:"
          ),
          tags$ol(
            tags$li(
              "the module given in the tool's ", tags$code("_module"),
              " argument (a module id such as ", tags$code("demo"), ")"
            ),
            tags$li("the tab pinned with the ", as_icon("thumbtack"), " button"),
            tags$li("the tab you clicked or typed in most recently")
          ),
          tags$p(
            "Each result ends with a note such as ",
            tags$code("[shidashi] ran on demo (pinned)"), ". The ",
            tags$code("shidashi_sessions"), " tool lists the open tabs."
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

        # --- Claude Desktop config ---
        accordion_item(
          title = "Claude Desktop Configuration",
          tags$p(
            "Edit ", tags$code("claude_desktop_config.json"), " (on macOS: ",
            tags$code("~/Library/Application Support/Claude/"),
            "; on Windows: ", tags$code("%APPDATA%\\Claude\\"), "):"
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "json",
'{
  "mcpServers": {
    "shidashi": {
      "command": "node",
      "args": ["<PROXY_PATH>"]
    }
  }
}'
            )
          ),
          tags$p(
            "Quit and reopen Claude Desktop. The connector works even when no ",
            "app is running; the agent then asks you what to do."
          )
        ),

        # --- Saved apps ---
        accordion_item(
          title = "Saved Apps",
          tags$p(
            "Save an app so the agent can start it for you. Nothing starts on ",
            "its own: when no app is running, the agent asks whether you will ",
            "start one yourself or want it to launch a saved app, and which ",
            "module to open."
          ),
          tags$pre(
            class = "bg-gray-90 pre-compact",
            tags$code(
              class = "r",
'shidashi::save_launcher(
  "my-app", "/path/to/my/app",
  description = "What this app is for",
  port = NA,          # NA picks a free port
  copy_app = TRUE,    # run a copy kept in the shidashi cache folder
  lab = "neuro"       # other named values are metadata for the agent
)

# Start it yourself; extra arguments go to render()
shidashi::run_launcher("my-app", launch_browser = TRUE)'
            )
          ),
          tags$p(
            "The agent lists saved apps with ", tags$code("shidashi_launchers"),
            " and starts one with ", tags$code("shidashi_launch"),
            ", which also opens the chosen module in your browser."
          )
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
            tags$dt("\"No shidashi app is running\""),
            tags$dd(
              "Start the app with ", tags$code("shidashi::render()"),
              ", or save it with ", tags$code("shidashi::save_launcher()"),
              " so the agent can start it when you ask."
            ),

            tags$dt("\"No dashboard module is open\""),
            tags$dd(
              "Open a module that has AI agents (an ", tags$code("agents.yaml"),
              " file) in the browser, then ask again."
            ),

            tags$dt("\"Connection refused\""),
            tags$dd(
              "The Shiny app isn't running. Start it with ",
              tags$code("shidashi::render()"), "."
            ),

            tags$dt("Tools appear but calls fail"),
            tags$dd(
              "Check that the tool is turned on (", tags$code("enabled"),
              ") in the module's ", tags$code("agents.yaml"), ". Agent modes ",
              "and the confirmation policy only affect the dashboard chat."
            ),

            tags$dt("The agent acts in the wrong tab"),
            tags$dd(
              "Pin the tab you want with the ", as_icon("thumbtack"),
              " button, or ask the agent to pass ", tags$code("_module"), "."
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
