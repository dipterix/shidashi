# Chat-bot server logic (per-module)

Sets up the chat server for a single module. Creates its own
[`Chat`](https://ellmer.tidyverse.org/reference/Chat.html) object, binds
tools from the `MCP` session registry, and manages per-module
conversation history.

The function renders
[`chatbot_ui()`](https://dipterix.org/shidashi/reference/chatbot_ui.md)
into the drawer's `uiOutput` via
[`shiny::renderUI`](https://rdrr.io/pkg/shiny/man/renderUI.html), and
opens the drawer when a `"button.click"` shidashi-event with
`type = "open_drawer"` is received. Any element with
`data-shidashi-action="shidashi-button"`
`data-shidashi-type="open_drawer"` can trigger the drawer.

This function is injected into each module's server function by
`modules.R` when `agents.yaml` has `enabled: yes`. It is called inside
[`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html),
so `session` is module-scoped. shinychat operations use the scoped
`session`; only drawer and event operations use `session$rootScope()`.

## Usage

``` r
chatbot_server(
  input,
  output,
  session,
  id = "shidashi-chatbot",
  drawer_id = "shidashi_drawer",
  agent_conf = NULL
)
```

## Arguments

- input, output, session:

  Standard Shiny server arguments (typically module-scoped when inside
  `moduleServer`).

- id:

  character; must match the `id` used in
  [`chatbot_ui()`](https://dipterix.org/shidashi/reference/chatbot_ui.md).
  Default `"shidashi-chatbot"`.

- drawer_id:

  character; the output ID of the drawer's `uiOutput` placeholder (from
  [`module_drawer()`](https://dipterix.org/shidashi/reference/module_drawer.md)).
  Default `"shidashi_drawer"`.

- agent_conf:

  list; parsed `agents.yaml` content. Used for the system prompt and
  tool configuration.

## Value

Called for side effects (sets up observers). Returns `invisible(NULL)`.
