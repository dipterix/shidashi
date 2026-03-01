# AI Agent Integration via MCP (shidashi)

Expose shidashi Shiny tools to external AI agents (e.g., VS Code Copilot)
via the Model Context Protocol (MCP) Streamable HTTP transport. The MCP
endpoint lives inside the same httpuv process as the Shiny app — no
sidecar process needed.

## Architecture

```
VS Code Copilot (.vscode/mcp.json)
    |  POST http://localhost:PORT/mcp  (JSON-RPC 2.0)
    v
Shiny httpuv (same process, same port)
    |  adminlte_ui() -> function(req) intercepts /mcp
    |  returns shiny::httpResponse(application/json)
    v
MCP Handler (R/mcp-handler.R)
    |  dispatches: initialize / tools/list / tools/call
    v
Session Registry (package-level fastmap)
    |  token_A -> {session, tools, module_id, meta}
    |  token_B -> {session, tools, module_id, meta}
    v
Tool functions (closures capturing live Shiny sessions)
```

Key insight: Shiny's UI function `function(req)` can return
`shiny::httpResponse()` to bypass HTML rendering and serve raw
JSON. The MCP handler runs on the same httpuv event loop as Shiny,
so `session$sendCustomMessage()` and `shiny::isolate(session$input)`
work without cross-thread issues.

---

## Phase 1: MCP Tunnel with Hello-World Example

**Goal**: Prove that `/mcp` POST requests work inside a Shiny app,
returning JSON instead of HTML. No Shiny session tools yet — just a
static hello-world tool.

### Files to create/modify (in shidashi)

- **`R/mcp-handler.R`** (new) — MCP JSON-RPC protocol handler
- **`R/ui-adminlte.R`** (modify) — intercept `/mcp` in `adminlte_ui()`

### Step 1.1: Create `R/mcp-handler.R`

Implement `mcp_http_handler(req)` — the entry point called from
`adminlte_ui()` when `req$PATH_INFO == "/mcp"`:

1. Read body: `req$rook.input$read()` -> raw bytes -> `rawToChar()` ->
   `jsonlite::fromJSON()`
2. Extract `jsonrpc`, `method`, `id`, `params`
3. Dispatch:

| Method                       | Handler                    | Response          |
|------------------------------|----------------------------|-------------------|
| `initialize`                 | `mcp_handle_initialize()`  | 200 + JSON result |
| `notifications/initialized`  | no-op                      | 202 Accepted      |
| `tools/list`                 | `mcp_handle_tools_list()`  | 200 + JSON result |
| `tools/call`                 | `mcp_handle_tools_call()`  | 200 + JSON result |
| unknown                      | JSON-RPC error -32601      | 200 + JSON error  |

4. Return `shiny::httpResponse(status, "application/json", body)`
5. For notifications (no `id` field): return
   `shiny::httpResponse(202L, "", "")`

Implement `mcp_handle_initialize(id, params)`:

```json
{
  "jsonrpc": "2.0",
  "id": <id>,
  "result": {
    "protocolVersion": "2025-03-26",
    "capabilities": { "tools": {} },
    "serverInfo": { "name": "shidashi", "version": "<pkg version>" }
  }
}
```

Generate an `Mcp-Session-Id` (e.g., `digest::digest(Sys.time())`),
return it as an HTTP header. Store it in a package-level fastmap
`.mcp_state` for later session tracking.

Implement `mcp_handle_tools_list(id)` — for Phase 1, return a single
static hello-world tool:

```json
{
  "tools": [{
    "name": "hello_world",
    "description": "Returns a greeting. Used to verify the MCP tunnel works.",
    "inputSchema": {
      "type": "object",
      "properties": {
        "name": { "type": "string", "description": "Name to greet" }
      },
      "required": ["name"]
    }
  }]
}
```

Implement `mcp_handle_tools_call(id, params)` — look up tool by
`params$name`, call it, wrap result:

```json
{
  "content": [{ "type": "text", "text": "Hello, <name>!" }],
  "isError": false
}
```

### Step 1.2: Modify `adminlte_ui()`

In `R/ui-adminlte.R`, at the very top of the `function(req)` body
(before the existing `tryCatch`), add:

```r
# -- MCP endpoint --
if (grepl("^/mcp$", req$PATH_INFO)) {
  if (identical(req$REQUEST_METHOD, "POST")) {
    return(mcp_http_handler(req))
  }
  if (identical(req$REQUEST_METHOD, "DELETE")) {
    return(shiny::httpResponse(200L, "application/json", "{}"))
  }
  # GET (SSE) not supported
  return(shiny::httpResponse(405L, "", ""))
}
```

`shiny::httpResponse()` returns a raw HTTP response — Shiny does NOT
wrap it in HTML. This is the documented escape hatch.

### Step 1.3: Manual verification

1. Run `shidashi::render()` to launch the app (e.g., on port 7586)
2. From terminal:
   ```bash
   # Initialize
   curl -X POST http://localhost:7586/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

   # List tools
   curl -X POST http://localhost:7586/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

   # Call hello_world
   curl -X POST http://localhost:7586/mcp \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"hello_world","arguments":{"name":"World"}}}'
   ```
3. Configure VS Code:
   ```jsonc
   // .vscode/mcp.json
   {
     "servers": {
       "shidashi": {
         "type": "http",
         "url": "http://localhost:7586/mcp"
       }
     }
   }
   ```
4. Verify VS Code Copilot discovers `hello_world` and can call it.

### Deliverables

- [ ] `R/mcp-handler.R` with `mcp_http_handler()`, dispatchers, and
      hello-world tool
- [ ] Modified `adminlte_ui()` with `/mcp` route interception
- [ ] Successful curl round-trip for initialize / tools/list / tools/call
- [ ] VS Code Copilot connects and calls `hello_world`

---

## Phase 2: Wire Shiny Sessions and Build Input Tools

**Goal**: Create a session registry so the MCP handler can access live
Shiny sessions. Implement `list_sessions`, `select_session`, and
`get_input_values` tools.

### Files to create/modify (in shidashi)

- **`R/mcp-handler.R`** (extend) — session registry + session tools
- **`R/shared-session.R`** (modify) — register sessions for MCP on
  `register_session_id()`

### Step 2.1: Create session registry

In `R/mcp-handler.R`, add package-level storage:

```r
# Package-level session registry (survives across HTTP requests)
.mcp_registry <- new.env(parent = emptyenv())
.mcp_registry$sessions  <- fastmap::fastmap()  # token -> {session, tools, meta}
.mcp_registry$mcp_state <- fastmap::fastmap()  # mcp_sid -> {active_token}
```

Implement:

- `mcp_register_session(session, tools = list(), meta = list())` —
  stores `list(session = session, tools = tools, meta = meta)` in
  `.mcp_registry$sessions` keyed by `session$token`
- `mcp_unregister_session(session)` — removes the entry

### Step 2.2: Hook into `register_session_id()`

In `R/shared-session.R`, at the end of `register_session_id()` (before
the return), add:

```r
# Register for MCP access
if (!is.null(session$token)) {
  mcp_register_session(
    session = session,
    tools = list(),
    meta = list(
      namespace = tryCatch(session$ns(""), error = function(e) ""),
      url = tryCatch(
        shiny::isolate(session$clientData$url_search),
        error = function(e) ""
      )
    )
  )
  session$onSessionEnded(function() {
    mcp_unregister_session(session)
  })
}
```

### Step 2.3: Implement session management tools

Replace the hello-world tool with three tools in
`mcp_handle_tools_list()`:

**`list_sessions`** — returns all registered Shiny sessions:

```json
{
  "name": "list_sessions",
  "description": "List all active Shiny sessions. Each session represents a browser tab or iframe. Returns token, namespace, URL, and available tool count.",
  "inputSchema": { "type": "object", "properties": {} }
}
```

Implementation: iterate `.mcp_registry$sessions`, return JSON array of
`{token, namespace, url, tool_count, connected_at}`.

**`select_session`** — set the active session for this MCP client:

```json
{
  "name": "select_session",
  "description": "Select a Shiny session to interact with. Use list_sessions first to see available sessions. All subsequent tool calls will target this session.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "token": { "type": "string", "description": "Session token from list_sessions" }
    },
    "required": ["token"]
  }
}
```

Implementation: validate token exists in registry, store
`active_token` in `.mcp_registry$mcp_state[mcp_session_id]$active`.

**`get_input_values`** — read live Shiny input values:

```json
{
  "name": "get_input_values",
  "description": "Read current values of Shiny inputs from the active session. Returns a JSON object mapping each inputId to its current value. Pass an empty array to read all inputs.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "input_ids": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Array of Shiny input IDs to read. Empty array returns all inputs."
      }
    },
    "required": ["input_ids"]
  }
}
```

Implementation:

1. Look up active session from `.mcp_registry$mcp_state[mcp_sid]$active`
2. Get the live `session` object from `.mcp_registry$sessions[[token]]$session`
3. Use `shiny::isolate(session$input[[id]])` to read values
4. If `input_ids` is empty, use
   `shiny::isolate(shiny::reactiveValuesToList(session$input))` for all
5. Return JSON

Error cases:
- No active session selected -> error message prompting `select_session`
- Active session disconnected -> error message, remove stale entry,
  suggest `list_sessions`

### Step 2.4: Verification

1. Launch shidashi app, open two browser tabs
2. VS Code: call `list_sessions` -> see two entries with tokens
3. Call `select_session` with one token
4. Call `get_input_values` with `["some_input_id"]` -> see live value
5. Change slider in browser -> call `get_input_values` again -> see
   updated value
6. Close Tab A -> call `get_input_values` -> get "session disconnected"
   error with prompt to call `list_sessions`

### Deliverables

- [ ] Session registry (`.mcp_registry`) in `R/mcp-handler.R`
- [ ] `mcp_register_session()` / `mcp_unregister_session()` helpers
- [ ] `register_session_id()` hook in `R/shared-session.R`
- [ ] `list_sessions`, `select_session`, `get_input_values` MCP tools
- [ ] Multi-tab test: two browser sessions, switch between them via MCP

---

## Phase 3: Per-Module Tool Configuration

**Goal**: Each shidashi module controls which MCP tools are available
via an R script (`R/mcp-tools.R`). The MCP handler loads tools per
session. Users can also define system prompts and skill descriptions
per module. A `list_session_tools` MCP tool exposes what is available
in each session.

### Files to create/modify (in shidashi)

- **`R/mcp-tools-discover.R`** (new) — tool discovery from R scripts
- **`R/mcp-handler.R`** (extend) — tool discovery + per-module filtering
- **`R/shared-session.R`** (modify) — auto-register module tools on
  session start
- **Template files** — example `mcp-tools.R` at root and per module

### Step 3.1: Define the module MCP config convention

Each module can optionally contain `R/mcp-tools.R`. The project root
can also have `R/mcp-tools.R` for global tools available in all
sessions:

```
{shidashi_project}/
  R/
    common.R              # existing
    mcp-tools.R           # NEW optional: global tools
  modules/
    demo/
      R/
        demo-ui.R         # existing
        mcp-tools.R       # NEW optional: demo module tools
      server.R
      module-ui.html
```

Each `mcp-tools.R` may define:

| Symbol              | Type                  | Required | Purpose                                   |
|---------------------|-----------------------|----------|-------------------------------------------|
| `mcp_tools`         | `function(session)`   | Yes      | Returns named list of `ellmer::ToolDef`   |
| `mcp_system_prompt` | `character`           | No       | System prompt hint for AI agents          |
| `mcp_skills`        | `list` of `list`      | No       | Skill descriptions (name, description)   |

### Step 3.2: Tool discovery function

In `R/mcp-tools-discover.R`, implement
`mcp_discover_tools(root_path, module_id = NULL)`:

1. Source `{root_path}/R/mcp-tools.R` if it exists ->
   extract `mcp_tools`, `mcp_system_prompt`, `mcp_skills`
2. If `module_id` given, also source
   `{root_path}/modules/{module_id}/R/mcp-tools.R` if it exists ->
   module-level definitions override/extend global ones
3. Return a list:
   ```r
   list(
     tool_factory = <function(session)>,  # merged factory
     system_prompt = <character or NULL>,
     skills = <list or NULL>
   )
   ```

Cache sourced environments per `root_path + module_id`, invalidated
when file mtime changes (use `file.info()$mtime` comparison).

### Step 3.3: Auto-register tools when session starts

Modify `mcp_register_session()` or add `register_mcp_tools(session,
tools, meta)` exported function. The session's module ID is available
as `.module_id` in the module environment.

Option A — **explicit**: the template `server.R` calls:
```r
server <- function(input, output, session, ...) {
  shidashi::register_session_id(session)  # existing
  shidashi::register_mcp_tools(           # NEW
    session = session,
    root_path = shidashi::template_root(),
    module_id = .module_id                # set by load_module()
  )
  ...
}
```

Option B — **automatic**: `register_session_id()` calls
`mcp_discover_tools()` internally using module context from the
session URL. Less explicit but zero boilerplate for module authors.

Decide which option to implement based on how reliably `.module_id` is
accessible at the time `register_session_id()` runs.

### Step 3.4: `list_session_tools` MCP tool

Add a new built-in MCP tool exposed in `tools/list`:

```json
{
  "name": "list_session_tools",
  "description": "List tools available for a specific session. Different sessions may expose different tools depending on which module is active. Also returns system prompt and skills if defined.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "token": {
        "type": "string",
        "description": "Session token. If omitted, uses the currently active session."
      }
    }
  }
}
```

Returns:
```json
{
  "token": "abc123",
  "module_id": "demo",
  "system_prompt": "This module shows a histogram...",
  "skills": [{"name": "histogram_control", "description": "..."}],
  "tools": [
    {"name": "shiny_list_inputs", "description": "..."},
    {"name": "shiny_update_inputs", "description": "..."}
  ]
}
```

### Step 3.5: Tool access control in `tools/call`

When `tools/call` is received for a non-built-in tool:

1. Look up active session token
2. Check if the requested tool name is in that session's registered
   tools (`.mcp_registry$sessions[[token]]$tools`)
3. If not in scope -> return `isError: true`:
   ```
   "Tool 'shiny_update_inputs' is not available in the current session
   (module: getstarted). Call list_session_tools to see available tools,
   or select_session to switch to a different session."
   ```
4. If in scope -> call `tool@fun(...)` with the provided arguments

### Step 3.6: `get_session_info` MCP tool

Add a companion tool to expose the system prompt and skills for the
active session without listing all tools:

```json
{
  "name": "get_session_info",
  "description": "Get the system prompt and skill descriptions for the active session. Use this to understand the context and domain of the current module.",
  "inputSchema": { "type": "object", "properties": {} }
}
```

### Step 3.7: Update `tools/list` to be dynamic

`mcp_handle_tools_list()` should return the **union** of:
1. Built-in infrastructure tools (always present):
   `list_sessions`, `select_session`, `list_session_tools`,
   `get_session_info`
2. All tools across all currently registered sessions (deduplicated
   by name, annotated with `description` from the first occurrence)

This gives the AI agent a full picture upfront. Per-session filtering
and access control happen at `tools/call` time (Step 3.5).

### Step 3.8: Update bslib-bare template

Add `R/mcp-tools.R` to the project root:

```r
# R/mcp-tools.R
# Global MCP tools available in every session of this shidashi app.
# Define mcp_tools(session) returning a named list of
# ellmer::ToolDef objects.

mcp_system_prompt <- "This is a shidashi dashboard application."

mcp_tools <- function(session) {
  list()  # no global tools by default; add here or in each module
}
```

Add `modules/demo/R/mcp-tools.R`:

```r
# MCP tools for the demo module

mcp_system_prompt <- paste(
  "This module shows a demo histogram with adjustable bins.",
  "Use get_input_values to check current state before updating.",
  "The nbins input controls histogram bin count (integer, 1-200).",
  "The txt input sets the histogram title (string)."
)

mcp_skills <- list(
  list(
    name = "adjust_histogram",
    description = "Change bin count or title via nbins and txt inputs"
  )
)

mcp_tools <- function(session) {
  shidashi::shiny_mcp_tools(
    session = session,
    input_types = data.frame(
      inputId   = c("nbins", "txt"),
      type      = c("numericInput", "textInput"),
      update_fn = c("shiny::updateNumericInput",
                     "shiny::updateTextInput")
    )
  )
}
```

Update the template `server.R` to call `register_mcp_tools()`:

```r
server <- function(input, output, session) {
  shared_data <- shidashi::register_session_id(session)
  shared_data$enable_broadcast()
  shared_data$enable_sync()

  shidashi::register_mcp_tools(           # NEW
    session = session,
    root_path = shidashi::template_root(),
    module_id = get0(".module_id", inherits = FALSE)
  )

  shiny::observeEvent(session$clientData$url_search, {
    ...  # existing module dispatch
  })
}
```

### Step 3.9: Verification

1. Launch app, navigate to demo module in Tab A, getstarted in Tab B
2. VS Code: `list_sessions` -> see two tabs with their module IDs
3. `select_session` Tab A -> `list_session_tools` -> see demo tools +
   system prompt
4. `select_session` Tab B -> `list_session_tools` -> tools list empty
   (getstarted has no mcp-tools.R) or only global tools
5. Call `shiny_update_inputs` while Tab B is selected -> rejected with
   helpful message
6. Switch to Tab A -> same call succeeds

### Deliverables

- [ ] `R/mcp-tools-discover.R` with `mcp_discover_tools()` + mtime
      caching
- [ ] `register_mcp_tools()` exported function in shidashi
- [ ] `list_session_tools`, `get_session_info` built-in MCP tools
- [ ] Tool access control in `tools/call` with session-scoped filtering
- [ ] Dynamic `tools/list` returning union across all sessions
- [ ] Template: root `R/mcp-tools.R` + `modules/demo/R/mcp-tools.R`
- [ ] Updated template `server.R` calling `register_mcp_tools()`
- [ ] Multi-module test: correct filtering, helpful error messages

---

## Dependencies (shidashi)

| Package    | Usage                                     | Type     |
|------------|-------------------------------------------|----------|
| jsonlite   | JSON parsing / serialization              | Imports (already) |
| fastmap    | Session registry                          | Imports (already) |
| digest     | MCP session ID generation                 | Imports (already) |
| ellmer     | `ToolDef` objects in app `mcp-tools.R`   | Suggests (new)    |
| shinychat | ui for ai chats | Suggests    |

No new hard dependencies required for shidashi itself.

## VS Code Configuration

After launching a shidashi app (e.g., on port 7586), add to
`.vscode/mcp.json` in your workspace:

```jsonc
{
  "servers": {
    "shidashi": {
      "type": "http",
      "url": "http://localhost:7586/mcp"
    }
  }
}
```
