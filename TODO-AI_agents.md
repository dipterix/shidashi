# AI Agent Integration via MCP (shidashi)

Expose shidashi Shiny tools to external AI agents (e.g., VS Code Copilot)
via the Model Context Protocol (MCP) Streamable HTTP transport. The MCP
endpoint lives inside the same httpuv process as the Shiny app — no
sidecar process needed.

## Naming Convention

MCP tools that interact with Shiny sessions use the `shiny` prefix to
avoid confusion with MCP protocol-level sessions:

- `list_shinysessions` — list live Shiny browser/iframe sessions
- `get_shiny_input_values` — read `session$input` (takes `token` param)

The word "session" alone is ambiguous (MCP session ID vs Shiny
`session$token`). `session$token` is unique per websocket connection —
each browser tab or iframe gets a distinct 32-hex-char token generated
by `createUniqueId(16)` inside `ShinySession$initialize()`.

## Architecture (actual)

```
VS Code Copilot (.vscode/mcp.json)
    |  POST http://localhost:PORT/mcp  (JSON-RPC 2.0)
    v
shinyApp()$httpHandler  (app-level, runs before Shiny routing)
    |  mcp_app_handler() intercepts /mcp
    |  POST -> mcp_http_handler(req)
    |  GET  -> info JSON
    |  DELETE -> 200 {}
    v
MCP Handler (R/mcp-handler.R)
    |  dispatches: initialize / tools/list / tools/call
    v
Shiny Session Registry (package-level fastmap via mcp_session_registry())
    |  token_A -> {session, meta}
    |  token_B -> {session, meta}
    v
Tool functions (closures reading live session$input)
```

**Key routing detail**: Shiny's `uiHttpHandler` only forwards GET
requests to the UI function (`function(req)`). POST/DELETE never reach
`adminlte_ui()`. The MCP endpoint therefore uses
`shinyApp()$httpHandler` — an app-level HTTP handler that runs before
Shiny's internal routing. `render()` builds the `shinyApp()` object
directly (not via `shinyAppDir()`), attaches `mcp_app_handler()` to
`app$httpHandler`, then calls `runApp(appDir = app)`.

---

## Phase 1: MCP Tunnel + Session Registry ✅

**Status**: Implemented and tested.

### What was built

#### `R/mcp-handler.R` (new, ~450 lines)

**Session registry** — singleton fastmap via closure:

```r
mcp_session_registry <- local({
  registry <- NULL
  function() {
    if (is.null(registry)) registry <<- fastmap::fastmap()
    registry
  }
})
```

Single fastmap keyed by `session$token`. Each value is a flat named list:

```r
list(
  shiny_session      = <ShinySession>,   # live session object
  shidashi_module_id = NULL,             # reserved for Phase 3
  namespace          = "",               # session namespace string
  url                = "",               # client URL at connect time
  registered_at      = <POSIXct>         # registration timestamp
)
```

No secondary map exists. Tools that need a Shiny session take `token`
directly as a parameter.

**Registry helpers**:

- `mcp_register_session(session, meta)` — stores flat entry, registers
  `onSessionEnded` callback for automatic cleanup
- `mcp_unregister_session(session)` — removes by token
- `mcp_sweep_closed_sessions()` — defensive `isClosed()` sweep on
  every MCP request (belt + suspenders)
- `mcp_get_shiny_entry(token)` — O(1) registry lookup, returns entry
  or NULL if not found / closed

**App-level HTTP handler** — `mcp_app_handler()`:

Returns a function for `shinyApp()$httpHandler`. Routes:
- `POST /mcp` → `mcp_http_handler(req)` (JSON-RPC dispatch)
- `DELETE /mcp` → 200 `{}`
- `GET /mcp` → 200 info JSON
- other methods → 405

**JSON-RPC dispatcher** — `mcp_http_handler(req)`:

1. Sweeps stale sessions
2. Reads body via `req$rook.input$read()`
3. Parses JSON, validates JSON-RPC 2.0 envelope
4. Notifications (no `id`) → 202 Accepted
5. Dispatches: `initialize`, `tools/list`, `tools/call`

**Protocol handlers**:

- `mcp_handle_initialize()` — generates `Mcp-Session-Id` via
  `digest::digest(sha256)`, returns `protocolVersion`, `capabilities`,
  `serverInfo`
- `mcp_handle_tools_list()` — returns tool definitions
- `mcp_handle_tools_call()` — dispatches to tool implementations

**Tools (Phase 1)**:

| Tool | Description |
|------|-------------|
| `hello_world` | Static greeting to verify tunnel works |
| `list_shinysessions` | Lists active Shiny sessions (token, namespace, url, registered_at) |

**JSON helpers**: `mcp_json_error()`, `mcp_json_response()`

#### `R/render.R` (modified)

`render()` now builds `shinyApp()` directly instead of using
`runApp(appDir = path)`:

```r
env <- new.env(parent = globalenv())
source(file.path(root_path, "server.R"), local = env)
app <- shiny::shinyApp(ui = shidashi::adminlte_ui(), server = env$server)
app$httpHandler <- mcp_app_handler()
shiny::runApp(appDir = app, ...)
```

This is necessary because `shinyAppDir()` prefers `server.R` over
`app.R`, so we cannot set `httpHandler` via an `app.R` file. Both the
interactive path and the RStudio job path use this pattern.

#### `R/shared-session.R` (modified)

At the end of `register_session_id()`, added:

```r
if (!is_registerd && !is.null(session$token)) {
  mcp_register_session(session = session, meta = list(
    namespace = tryCatch(session$ns(""), error = function(e) ""),
    url = tryCatch(shiny::isolate(session$clientData$url_search),
                   error = function(e) "")
  ))
}
```

The `is_registerd` flag (existing code) prevents double-registration
on reconnect. `onSessionEnded` cleanup is handled inside
`mcp_register_session()`.

#### `R/ui-adminlte.R` (unchanged)

Originally planned to intercept `/mcp` here, but Shiny only passes GET
requests to the UI function. POST routing is handled entirely by
`mcp_app_handler()` at the app level.

### Verification (completed)

```bash
# Initialize
curl -s -X POST http://127.0.0.1:6564/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}'
# → 200, Mcp-Session-Id header, serverInfo

# tools/list
curl -s -X POST http://127.0.0.1:6564/mcp \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <sid>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
# → 200, tools array

# tools/call hello_world
curl -s -X POST http://127.0.0.1:6564/mcp \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <sid>" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"hello_world","arguments":{"name":"Copilot"}}}'
# → "Hello, Copilot!"

# GET /mcp (info)
curl -s http://127.0.0.1:6564/mcp
# → {"status":"ok","message":"shidashi MCP endpoint active..."}

# DELETE /mcp
curl -s -X DELETE http://127.0.0.1:6564/mcp -H "Mcp-Session-Id: <sid>"
# → {}
```

### Dependencies

No new dependencies. All already in `Imports`: `jsonlite`, `fastmap`,
`digest`.

---

## Dev Testing Convention

Every MCP tool (and the tunnel itself) must have a non-official dev
test under `adhoc/mcp/`. These are **not** part of the R package test
suite (`tests/`) — they require a live running app and are run
manually from a terminal.

### Files

| File | Purpose |
|------|---------|
| `adhoc/mcp/launch.R` | Start bslib-bare at port 6564 (foreground, blocking) |
| `adhoc/mcp/test_mcp_tools.sh` | Curl-based end-to-end test for all MCP tools |

### Convention for new tools

When a new MCP tool is added:
1. Add at least one test block to `adhoc/mcp/test_mcp_tools.sh`
   covering the happy path and one error path.
2. Document expected output in a comment block above the curl call.
3. Run `adhoc/mcp/test_mcp_tools.sh` before committing to verify no
   regression.

---

## Phase 2: Shiny Session Interaction Tools ✅

**Status**: Implemented.

### Tool inventory

| Tool | Description | Inputs |
|------|-------------|--------|
| `hello_world` | Verify tunnel works | `name: string` |
| `list_shinysessions` | List active Shiny sessions | (none) |
| `get_shiny_input_values` | Read input values from a session | `token: string` (required), `input_ids: string[]` (optional) |

### Implementation

#### Stateless token-passing

Each tool that needs a Shiny session takes `token` directly as a
required parameter. No stateful cursor or session binding — each tool
call is self-contained:

```r
# get_shiny_input_values resolves session via O(1) lookup:
mcp_get_shiny_entry(token)   # registry$get(token), checks not closed
```

The `Mcp-Session-Id` header is still generated on `initialize` and
echoed on responses (MCP protocol requirement) but is **not** stored
in registry entries or used for Shiny session lookup.

### Verification

See `adhoc/mcp/test_mcp_tools.sh` for the full test sequence. Steps
that require a browser tab are skipped automatically when no sessions
are registered, with a hint to open the app URL.

Quick manual sequence:

```bash
# Terminal 1 — start app
Rscript adhoc/mcp/launch.R

# Browser — open http://127.0.0.1:6564

# Terminal 2 — run tests
bash adhoc/mcp/test_mcp_tools.sh
```

---

## Phase 3: Dynamic Per-Module MCP Tools ✅

**Goal**: Refactor MCP tools from hardcoded handlers into a dynamic,
per-session system. Tool authors write `mcp_wrapper()` generators in
`agents/tools/*.R`. Modules opt into root-level tools via
`agents/agent.yaml`. The MCP session binds to a Shiny session via a
built-in `register_shinysession` tool — after binding, per-session
tools become callable.

### Naming convention

Tools exposed via MCP use the prefix pattern:

```
tool__{module_id}__{tool_name}
```

Skills (Phase 4) will use `skill__{module_id}__{skill_name}`.

Built-in infrastructure tools have no prefix:
`list_shinysessions`, `register_shinysession`, `get_session_info`.

### Architecture

```
agents/tools/*.R            ← root-level tool generators (opt-in per module)
modules/{id}/agents/tools/  ← module-level tool generators (auto-enabled)
modules/{id}/agents/agent.yaml ← permissions: which root tools to enable
```

**Stateful binding**: After `initialize`, the MCP session is unbound.
The agent calls `register_shinysession(token)` to bind. Once bound,
all per-session tools for that Shiny session become available. The
agent can switch sessions by calling `register_shinysession` again.

### Package files

| File | Status | Purpose |
|------|--------|---------|
| `R/mcp-wrapper.R` | new | `mcp_wrapper()` constructor + `is_mcp_wrapper()` |
| `R/mcp-discover.R` | new | `mcp_discover_generators()`, `mcp_read_agent_yaml()`, `mcp_instantiate_tools()`, `mcp_tooldef_to_schema()`, `register_mcp_tools()` |
| `R/mcp-handler.R` | modified | Session binding state, dynamic `tools/list` + `tools/call`, built-in `register_shinysession` + `get_session_info` |
| `DESCRIPTION` | modified | `ellmer (>= 0.1.0)` in Suggests |

### `mcp_wrapper()` API

```r
# Template author writes in agents/tools/my_tool.R:
my_tool <- shidashi::mcp_wrapper(function(input, output, session,
                                          reactive_values, shared_env) {
  ellmer::tool(
    fun = function(x) { ... },
    name = "my_tool",
    description = "Does something",
    arguments = list(x = ellmer::type_string("..."))
  )
})
```

The `mcp_wrapper` is a closure factory. The 5-arg generator receives
the live Shiny session context. It returns one `ellmer::ToolDef` or
a named list of them. The AI agent never sees these 5 args — they
are enclosed at session registration time.

### `agent.yaml` schema

```yaml
tools:
  root:
    hello_world: true             # enable this root tool
    get_shiny_input_values: true  # enable this root tool
    # tools not listed: banned (not available)
```

Module-local tools (from `modules/{id}/agents/tools/`) are always
enabled — no need to list them.

### Built-in tools (always available)

| Tool | Description |
|------|-------------|
| `list_shinysessions` | List active Shiny sessions with module_id and tool names |
| `register_shinysession` | Bind MCP session to a Shiny session by token |
| `get_session_info` | Show current binding status and available tools |

### Dynamic dispatch

- `tools/list`: returns built-in tools always. If bound, also returns
  per-session tools (with `tool__{module_id}__` prefix).
- `tools/call`: built-in tools dispatch directly. Per-session tools
  require binding — look up bound session → find tool → call
  `tool_def(...)` via S7 callable dispatch.

### Template files

| File | Purpose |
|------|---------|
| `agents/tools/hello_world.R` | Root-level hello_world mcp_wrapper |
| `agents/tools/get_shiny_input_values.R` | Root-level input reader |
| `modules/demo/agents/tools/trigger_refresh.R` | Demo module tool |
| `modules/demo/agents/agent.yaml` | Enables root tools for demo |

### Deliverables

- [x] `R/mcp-wrapper.R` with `mcp_wrapper()`, `is_mcp_wrapper()`
- [x] `R/mcp-discover.R` with discovery + instantiation + schema conversion
- [x] `register_mcp_tools()` exported function
- [x] Session binding state (`mcp_session_bindings()` fastmap)
- [x] `register_shinysession`, `get_session_info` built-in MCP tools
- [x] Dynamic `tools/list` and `tools/call` with binding enforcement
- [x] Template: root `agents/tools/` + `modules/demo/agents/`
- [x] Updated `adhoc/mcp/test_mcp_tools.sh`

---

## Phase 4: Skills (future)

**Goal**: Add skill wrappers (`skill_wrapper()`) with progressive
disclosure pattern (tricobbler-style). Skills use the prefix
`skill__{module_id}__{skill_name}`. Defined in `agents/skills/*.R`.
Permissions controlled via `agent.yaml`. `processx` in Suggests for
background execution.

*Not yet implemented.*

---

## Dependencies (shidashi)

| Package    | Usage                                     | Type              |
|------------|-------------------------------------------|-------------------|
| jsonlite   | JSON parsing / serialization              | Imports (already) |
| fastmap    | Session registry, active-session map      | Imports (already) |
| digest     | MCP session ID generation                 | Imports (already) |
| ellmer     | `ToolDef` objects for MCP tools           | Suggests (new)    |
| shinychat  | UI for AI chats                           | Suggests          |
| processx   | Background skill execution (Phase 4)      | Suggests          |

No new hard dependencies required for shidashi itself.

## VS Code Configuration

After launching a shidashi app (e.g., on port 6564), add to
`.vscode/mcp.json` in your workspace:

```jsonc
{
  "servers": {
    "shidashi": {
      "type": "http",
      "url": "http://localhost:6564/mcp"
    }
  }
}
```
