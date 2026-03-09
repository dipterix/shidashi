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
`adminlte_ui()`. The MCP endpoint is attached via `register_mcp_route()`,
which wraps the existing `shinyApp$httpHandler` produced by
`shiny::shinyAppDir()` and injects the MCP handler in front of it.

---

## Phase 1: MCP Tunnel + Session Registry ✅

**Status**: Implemented and tested.

### What was built

#### `R/mcp-handler.R` (new, ~914 lines)

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

Single fastmap keyed by `session$token`. Each value is a named list:

```r
list(
  shiny_session      = <ShinySession>,   # live session object
  shidashi_module_id = NULL,             # set during Phase 3 module load
  mcp_session_ids    = character(),      # MCP session IDs bound to this entry
  namespace          = "",               # session$ns(NULL)
  url                = "",               # client URL at connect time
  registered_at      = <POSIXct>,        # registration timestamp
  tools              = list()            # named list of ellmer::ToolDef (Phase 3)
)
```

**Registry helpers**:

- `register_session_mcp(session)` — stores entry, registers
  `onSessionEnded` callback for automatic cleanup; called from `modules.R`
- `mcp_unregister_session(session)` — removes by token
- `mcp_sweep_closed_sessions()` — defensive `isClosed()` sweep on
  every MCP request (belt + suspenders)
- `mcp_get_shiny_entry(token)` — O(1) registry lookup, returns entry
  or NULL if not found / closed
- `mcp_tool_bound_shinysessions(mcp_session_id)` — returns Shiny tokens
  bound to a given MCP session ID
- `mcp_tool_unregister_shinysession(mcp_session_id)` — unbinds MCP
  session from all Shiny tokens

**App-level HTTP handler** — `register_mcp_route(app)`:

Wraps an existing `shinyApp` object's `httpHandler`. Routes:
- `POST /mcp` → `mcp_http_handler(req)` (JSON-RPC dispatch)
- `DELETE /mcp` → 200 `{}` + unregisters MCP session binding
- `GET /mcp` → 200 info JSON
- other methods / paths → delegated to original handler

Also excludes `/mcp` from httpuv static-path handling so POST/DELETE
reach the R handler instead of being rejected with 400.

**JSON-RPC dispatcher** — `mcp_http_handler(req)`:

1. Sweeps stale sessions
2. Reads body via `req$rook.input$read()`
3. Parses JSON, validates JSON-RPC 2.0 envelope
4. Notifications (no `id`) → 202 Accepted
5. Dispatches: `initialize`, `tools/list`, `tools/call`, `ping`

**Protocol handlers**:

- `mcp_handle_initialize()` — generates `Mcp-Session-Id` via
  `digest::digest(sha256)`, returns `protocolVersion = "2025-03-26"`,
  `capabilities`, `serverInfo`
- `mcp_handle_ping()` — returns empty result
- `mcp_handle_tools_list()` — returns built-in + per-session tools
- `mcp_handle_tools_call()` — dispatches to tool implementations

**Tools (Phase 1 built-ins, always available)**:

| Tool | Description |
|------|-------------|
| `list_shinysessions` | Lists active Shiny sessions (token, module_id, tool_names, registered_at) |
| `register_shinysession` | Bind MCP session to a Shiny session by token |
| `get_session_info` | Show current binding status and available tools |

**JSON helpers**: `mcp_json_error()`, `mcp_json_result()`
  (`mcp_json_result` supports both `application/json` and
  `text/event-stream` for SSE notifications)

#### `R/mcp-wrapper.R` (new)

Contains `mcp_wrapper()` constructor and `setup_mcp_proxy()`. The
`setup_mcp_proxy()` function writes port records and copies
`inst/mcp-proxy/shidashi-proxy.mjs` to the user cache; called from
`render()` on every launch.

#### `R/render.R` (modified)

`render()` resolves or picks a random port, calls `setup_mcp_proxy()`,
then uses `register_mcp_route(shiny::shinyAppDir(root_path))` to
attach the MCP handler before running the app:

```r
app <- register_mcp_route(shiny::shinyAppDir(root_path))
do.call(shiny::runApp, c(list(appDir = app, ...), dots))
```

Both the interactive path and the RStudio job path use this pattern.
The `ui.R` inside `root_path` is rewritten at launch time to inject
`template_settings$set('root_path' = ...)` so `shinyAppDir` uses the
correct path regardless of working directory.

#### `R/modules.R` (modified)

Session MCP registration happens inside module server injection (Phase 3
architecture), not in `shared-session.R`. Each module's server function
body is prepended with a block that calls `register_session_mcp(session)`
and then populates `entry$tools` from the module's tool generators.

#### `R/ui-adminlte.R` (unchanged)

Shiny passes only GET requests to the UI function; POST/DELETE are
handled by `register_mcp_route()` at the app level.

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
| `hello_world` | Verify tunnel works | `name: string` (optional) |
| `list_shinysessions` | List active Shiny sessions with module_id and tool names | (none) |
| `register_shinysession` | Bind MCP session to a Shiny session | `token: string` (required) |
| `get_session_info` | Show current binding and available tools | (none) |
| `get_shiny_input_values` | Read input values from the **bound** session | `input_ids: string[]` (optional) |

### Implementation

#### Stateful session binding

`hello_world` and `get_shiny_input_values` are **not** hardcoded in
`mcp-handler.R`. They live as `mcp_wrapper()` generators in
`agents/tools/hello_world.R` and `agents/tools/get_shiny_input_values.R`
and are instantiated with the live Shiny session at bind time.

The MCP session binds to a Shiny session via `register_shinysession`.
Binding is tracked in `entry$mcp_session_ids` (array) within the Shiny
session's registry entry — no separate binding map exists. After
binding, `get_shiny_input_values` reads from the enclosed `session`
captured in its closure:

```r
get_shiny_input_values <- shidashi::mcp_wrapper(
  function(session) {
    bound_session <- session   # captured in closure
    ellmer::tool(
      fun = function(input_ids = character()) {
        shiny::isolate(shiny::reactiveValuesToList(bound_session$input))
      }, ...
    )
  }
)
```

No `token` parameter is exposed to the AI agent — the session is
already resolved at registration time. The `Mcp-Session-Id` header is
generated on `initialize` and echoed on every response. On a successful
`register_shinysession` call, an SSE response with a
`notifications/tools/list_changed` notification is emitted so the
client refreshes its tool catalogue.

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

**Goal**: Turn Anthropic-compliant skill directories (`SKILL.md` +
optional `scripts/` + reference files) into single MCP tools via
closure-based `skill_wrapper()`. Each skill becomes one tool named
`skill__{namespace}__{sanitized_name}` that dispatches on an `action`
enum (`readme` / `reference` / `script`). A server-side gate rejects
premature script/reference calls with a condensed auto-generated
summary (~200 tokens) embedded in the error — teaching the AI in the
rejection itself, costing only 1 retry when the AI skips readme.

**Status**: Not yet implemented.

### Skill directory layout (Anthropic-compliant)

Skills live at the **root level only** (not per-module):
- `agents/skills/{skill-name}/SKILL.md`

Modules enable skills via their `agents.yaml` but skills are always
defined at the project root. This keeps skill definitions centralised
and avoids duplication across modules.

`SKILL.md` frontmatter uses standard Anthropic fields only:

```yaml
---
name: analyze-data
description: Runs the data analysis pipeline on selected inputs
---

## Instructions
When analyzing data:
1. Read the current input table with get_shiny_input_values
2. Run clean.R --threshold 0.05
3. Run analyze.R --input cleaned.csv
...
```

Supporting file conventions (matching Anthropic spec):

```
analyze-data/
├── SKILL.md              # required — frontmatter + instructions
├── reference.md          # optional — detailed API docs
├── examples/             # optional
│   └── sample-output.md
└── scripts/              # optional — CLI executables
    ├── analyze.R
    └── clean.R
```

### Naming convention

Per the Anthropic spec, the **folder name is the canonical skill
name**. No frontmatter `name` override. Discovery is a direct
lookup — no directory iteration needed. Missing folders are
silently dropped.

```
skill__{namespace}__{folder_name}
```

where `namespace` comes from `session$ns(NULL)` (e.g., `"demo"`).
This parallels the `tool__{namespace}__{tool_name}` convention from
Phase 3.

### Token-efficiency strategy: three tiers of detail

| Tier | Where | When loaded | Cost |
|------|-------|-------------|------|
| 1-line description | Tool `description` field in `tools/list` schema | Every request (prompt-cached) | ~30 tokens, effectively free |
| Condensed summary | Auto-generated from frontmatter + file inventory; embedded in gate error | Only when AI skips readme | ~150-200 tokens, 1 retry |
| Full instructions | SKILL.md body via `action=readme` | On-demand | 500-2000 tokens |

### Gate + condensed error mechanism

```r
# Auto-generated at closure creation time
condensed_summary <- paste0(
  "## ", skill_name, "\n",
  description, "\n\n",
  if (has_scripts) paste0("Scripts: ", paste(script_names, collapse=", "), "\n"),
  if (has_references) paste0("References: ", paste(ref_files, collapse=", "), "\n"),
  "\nCall action='readme' first, then retry."
)

tool_fn <- function(action, reference_kwargs = NULL, cli_kwargs = NULL) {
  if (action != "readme" && !readme_unlocked) {
    stop(
      "Read the skill guidelines first.\n\n",
      condensed_summary
    )
  }
  # ... dispatch
}
```

### Action dispatchers

- **`action=readme`**: Sets `readme_unlocked <<- TRUE` in closure.
  Returns SKILL.md body + runtime info. Full instructions — loaded
  only on-demand.
- **`action=reference`**: Takes `file_name`, optional `pattern`
  (grep), `line_start`, `n_rows`. Returns paginated file content.
  Gated behind readme.
- **`action=script`**: Takes `file_name`, `args`, optional `envs`.
  Runs via `processx::run()` with interpreter resolved from file
  extension (`.R` → Rscript, `.py` → python3, `.sh` → bash).
  Supports optional `runtime` config for virtualenv activation etc.
  Gated behind readme.

### Package files

| File | Status | Purpose |
|------|--------|---------|
| `R/skill-parse.R` | new | `parse_skill_md()`, `discover_references()`, `discover_scripts()`, `sanitize_skill_name()` |
| `R/skill-runner.R` | new | `build_script_command()`, script execution via `processx::run()` |
| `R/skill-wrapper.R` | new | `skill_wrapper()` constructor — takes skill dir path, returns closure with class `shidashi_skill_wrapper` that produces `ellmer::tool` per session |
| `R/modules.R` | modified | Scan `agents/skills/*/SKILL.md` (root + module level), wire into `tool_gen_fun` pipeline |
| `DESCRIPTION` | modified | `processx` in Suggests |

### `skill_wrapper()` API

```r
skill_wrapper(skill_path, runtime = NULL)
```

Returns a closure with class `shidashi_skill_wrapper`. The closure
accepts `session` (same interface as `mcp_wrapper`) and returns an
`ellmer::tool` that dispatches on `action`. No R6 — pure function
enclosure.

```r
# Example: auto-generated at discovery time in modules.R
wrapper <- skill_wrapper("agents/skills/analyze-data")

# At session bind time:
tool_def <- wrapper(session)  # returns ellmer::tool
```

### `agents.yaml` schema update

Skills listed alongside tools:

```yaml
tools:
- name: hello_world
  category: [exploratory]
  enabled: yes
skills:
- name: analyze-data
  category: [executing]
  enabled: yes
parameters:
  system_prompt: "You are an R shiny expert..."
```

Only skills with `enabled: yes` are active. Skills not listed are
excluded.

### Template demo skill

Create `agents/skills/greet/` (root-level):
- `SKILL.md` with Anthropic-compliant frontmatter
- `scripts/greet.R` — simple Rscript that prints a greeting

Update `modules/demo/agents.yaml` to enable it.

### Deliverables

- [ ] `R/skill-parse.R` with `parse_skill_md()`, `discover_references()`, `discover_scripts()`, `sanitize_skill_name()`
- [ ] `R/skill-runner.R` with `build_script_command()` + processx execution
- [ ] `R/skill-wrapper.R` with `skill_wrapper()` constructor
- [ ] `R/modules.R` updated to discover + wire skills
- [ ] `agents.yaml` schema extended for `skills:` list
- [ ] Template: `agents/skills/greet/` demo skill (root-level)
- [ ] Updated `adhoc/mcp/test_mcp_tools.sh` with skill tests (gate, readme, reference, script)

---

## Dependencies (shidashi)

| Package    | Usage                                     | Type              |
|------------|-------------------------------------------|-------------------|
| jsonlite   | JSON parsing / serialization              | Imports (already) |
| fastmap    | Session registry                          | Imports (already) |
| digest     | MCP session ID generation                 | Imports (already) |
| yaml       | Reading `agents.yaml` files               | Imports (already) |
| ellmer     | `ToolDef` objects, schema via `as_json`   | Suggests `>= 0.4.0` |
| shinychat  | UI for AI chats                           | Suggests          |
| processx   | Background skill execution (Phase 4)      | Suggests          |

No new hard dependencies required for shidashi itself.

## VS Code Configuration

`render()` calls `setup_mcp_proxy()` automatically and prints the
config snippet. The proxy (`inst/mcp-proxy/shidashi-proxy.mjs`) is a
Node.js stdio-to-HTTP bridge installed in the user cache. Add to
`.vscode/mcp.json`:

```jsonc
{
  "servers": {
    "shidashi": {
      "type": "stdio",
      "command": "node",
      "args": ["<path-to-cached-mcp-proxy.mjs>"]
    }
  }
}
```

To target a specific port (when multiple apps are running):

```jsonc
"args": ["<path-to-cached-mcp-proxy.mjs>", "6564"]
```

The proxy auto-discovers the most recent port record written to the
user cache when no port arg is given.

---

## Phase 6: In-App Chatbot Drawer

**Goal**: Add an AI chatbot panel inside the drawer that uses `ellmer::Chat`
with `shinychat` to let users interact with the active module's tools
directly from the Shiny app — no external MCP client needed.

### Key Architecture Principles

1. **ellmer direct integration, not MCP HTTP**: The chatbot calls
   `chat$register_tools(tool_list)` with R tool objects from the
   `.__shidashi_globals__.` registry. The `/mcp` HTTP endpoint is
   exclusively for **external** MCP clients (e.g. VS Code Copilot).
   The in-app chatbot never routes through HTTP.

2. **One session token per iframe**: Each iframe (module page) or root
   page has exactly **one** Shiny session and one `session$token` —
   analogous to `private_id`. In JS, `_sessionToken` is a single string,
   not a map. When a module registers via `register_session_mcp()`, it
   sends its token to JS via `shidashi.register_module_token`. JS stores
   it as a single value (overwritten on each module activation).

3. **Token included in `@shidashi_active_module@`**: The
   `_reportActiveModule(moduleId)` method now includes the token in the
   Shiny input: `{ module_id, token, timestamp }`. This lets R-side code
   (e.g. `chatbot_server()`) look up the active module's tools from the
   MCP registry keyed by token.

4. **JS fires event only — R opens the drawer**: When the chatbot FAB
   button is clicked, JS broadcasts a `shidashi-event` of type `chatbot`
   with `{ module_id, token }`. It does **not** open the drawer or switch
   tabs from JS. The R-side `chatbot_server()` observes this event, calls
   `shidashi::drawer_open(session)`, and handles all chat logic. This way,
   if the chatbot is disabled (no shinychat / `options(shidashi.chatbot =
   FALSE)`), the button simply does nothing.

### Design Decisions

- **Per-module chat sessions**: Separate `ellmer::Chat` objects per module,
  stored in `.__shidashi_globals__.$chat_sessions` (fastmap keyed by
  module_id). Switching modules switches the conversation context.
- **Tabbed drawer**: The drawer gets Bootstrap 5 nav-tabs: **Settings** tab
  (existing `drawer_ui()` content) and **Chat** tab (`chatbot_ui()` content).
- **Provider via `options()`**: `options(shidashi.chat_provider = "anthropic")`
  with optional `shidashi.chat_model` and `shidashi.chat_base_url`. The
  `init_chat()` function dispatches to the appropriate `ellmer::chat_*()`.
- **Conditional on shinychat**: Feature disabled when
  `options(shidashi.chatbot = FALSE)` or `shinychat` is not installed.
  `chatbot_ui()` returns empty `tagList()`; `chatbot_server()` no-ops.
- **FAB button**: A `.btn-chatbot` element added to `.shidashi-back-to-top`
  (via `back_top_button()`), with `data-shidashi-action="chatbot-toggle"`.

### Sub-phase 6a: Persist Session Token in JS

**`R/mcp-handler.R`** — In `register_session_mcp()`, after
`registry$set(token, entry)`, send the token to JS. Since this runs
inside a module iframe, use `session$sendCustomMessage()` directly
(module session and root session are the same Shiny websocket in iframe
context):

```r
session$sendCustomMessage("shidashi.register_module_token",
  list(module_id = namespace, token = token))
```

**`src/index.js`** — Add `_sessionToken = null` to `ShidashiApp`
constructor (single string, not a map). Add handler:

```js
this.shinyHandler('register_module_token', (params) => {
  this._sessionToken = params.token;
  // Re-report active module so R gets the updated token
  if (this._activeModuleId) {
    this._reportActiveModule(this._activeModuleId);
  }
});
```

**`_reportActiveModule(moduleId)`** — Include token:

```js
this._shiny.onInputChange('@shidashi_active_module@', {
  module_id: moduleId,
  token: this._sessionToken || null,
  timestamp: Date.now()
});
```

### Sub-phase 6b: Chatbot FAB Button

**`R/widgets.R`** — Modify `back_top_button()` to conditionally append
a chatbot button with `data-shidashi-action="chatbot-toggle"` and an
`fa-robot` icon. Only rendered when
`getOption("shidashi.chatbot", TRUE)` and `shinychat` is available.

**`src/shidashi.scss`** — `.btn-chatbot` in `.shidashi-back-to-top`:
round button with primary-color background, stacked above the existing
buttons.

**`src/index.js`** — On `chatbot-toggle` action: broadcast a
`shidashi-event` of type `chatbot` with
`{ module_id: this._activeModuleId, token: this._sessionToken }`.
**Do NOT open the drawer or switch tabs from JS.** R handles that.

### Sub-phase 6c: Tabbed Drawer

**`index.html`** — Restructure `.shidashi-drawer` content into two
BS5 nav-tabs: Settings and Chat:

```html
<ul class="nav nav-tabs shidashi-drawer-tabs" role="tablist">
  <li ...><button ... data-bs-target="#shidashi-drawer-settings">
    <i class="fas fa-cog"></i> Settings</button></li>
  <li ...><button ... data-bs-target="#shidashi-drawer-chat">
    <i class="fas fa-robot"></i> Chat</button></li>
</ul>
<div class="tab-content shidashi-drawer-tab-content">
  <div ... id="shidashi-drawer-settings">{{ drawer_ui() }}</div>
  <div ... id="shidashi-drawer-chat">{{ chatbot_ui() }}</div>
</div>
```

**`src/shidashi.scss`** — Drawer tabs fill remaining height. Chat pane:
flex column with messages scrollable and input pinned. Drawer width
increases to ~420px on hover/active.

### Sub-phase 6d: Chat State in `init_app()`

**`R/init-app.R`** — Add:

```r
global_env$chat_sessions        <- fastmap::fastmap()  # module_id -> Chat
global_env$module_agent_config  <- fastmap::fastmap()  # module_id -> params
```

**`R/modules.R`** — After parsing `agents.yaml`, store config:

```r
globals$module_agent_config$set(module_id, agent_conf$parameters)
```

### Sub-phase 6e: `init_chat()` Provider Factory

**`R/chatbot.R`** (new file):
- `init_chat(provider_name, model, base_url, module_id)` — reads
  options, creates `ellmer::Chat`, sets `system_prompt` from
  `module_agent_config`.
- Returns bare `Chat` (tools bound lazily by `chatbot_server()`).

### Sub-phase 6f: `chatbot_ui()` and `chatbot_server()`

**`chatbot_ui(id = "shidashi-chatbot")`**: Guard + `shinychat::chat_ui()`.

**`chatbot_server(id = "shidashi-chatbot", session)`**:
- Observes `@shidashi_event@` type `"chatbot"`:
  - Extracts `module_id`, `token`
  - Opens drawer via `shidashi::drawer_open(session)`
  - Creates or retrieves `Chat` from `chat_sessions` (keyed by module_id)
  - Finds tools from `mcp_session_registry()$get(token)$tools`
  - Calls `chat$register_tools(tools)` (ellmer direct, no HTTP)
  - Switches chat context in the UI
- Observes `input${id}_user_input`:
  - Streams via `chat$stream_async()` → `shinychat::chat_append()`

### Sub-phase 6g: Wire into Scaffolding

**`R/barebone.R`** — Generated `server.R` calls
`shidashi::chatbot_server()`. Generated `R/common.R` includes
`chatbot_ui <- function() shidashi::chatbot_ui()`.

### Sub-phase 6h: Module Switching

When the active module changes and the chatbot event fires again,
`chatbot_server()` swaps the `Chat` context: saves current turns
(already in Chat object), loads target module's Chat, replays
history.

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `R/chatbot.R` | **Create** | `init_chat()`, `chatbot_ui()`, `chatbot_server()` |
| `R/init-app.R` | Modify | Add `chat_sessions`, `module_agent_config` |
| `R/modules.R` | Modify | Store `agent_conf$parameters` in globals |
| `R/mcp-handler.R` | Modify | Send module token to JS (already done) |
| `R/widgets.R` | Modify | Add chatbot FAB to `back_top_button()` (already done) |
| `R/barebone.R` | Modify | Generated `server.R`/`common.R` call chatbot helpers |
| `src/index.js` | Modify | `_sessionToken` (single), include token in active module input, chatbot-toggle fires event only |
| `src/shidashi.scss` | Modify | Drawer tabs, chatbot button (partially done) |
| `index.html` | Modify | Tabbed drawer structure (already done) |
| `NAMESPACE` | Modify | Export `chatbot_ui`, `chatbot_server`, `init_chat` |
| `DESCRIPTION` | Modify | Add `shinychat` to Suggests |

---

## Phase 7: Mode-Based Permissions, `ask_user`, Destructive Confirmation

**Goal**: Implement runtime enforcement for the `agents.yaml`
modes/permissions schema. Each tool/skill `enabled` field can be `true`
(all modes) or a list of mode names (e.g. `["Plan", "Executing"]`).
Add a UI mode selector in the chatbot header, a built-in `ask_user` MCP
tool for interactive user prompts, and automatic confirmation prompts
for tools/scripts annotated with `category: [destructive]`. All async
via `promises` + `later`.

**Status**: Implemented.

### 7a: Mode State Management (R-side foundation)

#### `R/init-app.R` — Add `module_agent_modes` fastmap

New fastmap inside `.__shidashi_globals__.`, keyed by `module_id`.
Each value: `list(current_mode, modes, default_mode)`.

```r
global_env$module_agent_modes <- fastmap::fastmap()
```

#### `R/modules.R` — Store raw `enabled` values in annotations

Change `isTRUE(tool_conf$enabled)` to preserve the raw value for
mode-aware filtering:

```r
# Before (Phase 6):
tool@annotations$shidashi_enabled <- isTRUE(tool_conf$enabled)

# After (Phase 7):
tool@annotations$shidashi_enabled <- tool_conf$enabled
```

The value is either `TRUE`/`FALSE` (boolean) or a character vector of
mode names. Same change for skill annotations.

Additionally store per-script overrides on skill annotations:

```r
skill_tool@annotations$shidashi_skill_scripts <- skill_conf$scripts
```

And inject a mode-getter function so skill closures can check the
current mode at call time:

```r
tool@annotations$shidashi_get_mode <- function() {
  globals <- get_shidashi_globals()
  mode_entry <- globals$module_agent_modes$get(module_id)
  if (is.null(mode_entry)) return(NULL)
  mode_entry$current_mode
}
```

#### Helper functions (in `R/chatbot.R`)

```r
# Check if a tool is enabled for a given mode
is_tool_enabled_for_mode <- function(tool, mode) {
  enabled <- tool@annotations$shidashi_enabled
  if (is.null(enabled)) return(FALSE)
  if (isTRUE(enabled)) return(TRUE)
  if (isFALSE(enabled)) return(FALSE)
  mode %in% as.character(enabled)
}

# Check if a skill script is enabled for a given mode
is_script_enabled_for_mode <- function(skill_scripts, script_name, mode) {
  if (!length(skill_scripts)) return(TRUE)  # no overrides → skill-level
  for (sc in skill_scripts) {
    if (identical(sc$name, script_name)) {
      enabled <- sc$enabled
      if (is.null(enabled)) return(TRUE)
      if (isTRUE(enabled)) return(TRUE)
      if (isFALSE(enabled)) return(FALSE)
      return(mode %in% as.character(enabled))
    }
  }
  TRUE  # script not listed → falls back to skill-level
}
```

### 7b: UI — Mode Selector in Chatbot Header

#### `chatbot_ui()` — Add mode dropdown

New `selectInput` next to the conversation dropdown:

```r
shiny::div(
  class = "shidashi-chatbot-mode-select",
  shiny::selectInput(
    mode_select_id,
    label = NULL,
    choices = mode_choices,
    selected = default_mode,
    width = "100%"
  )
)
```

Choices populated from `agent_conf$modes` (`name` field), preselected
to `agent_conf$parameters$default_mode`.

#### `chatbot_server()` — Mode observer

```r
shiny::observeEvent(input[[mode_select_id]], {
  new_mode <- input[[mode_select_id]]
  globals$module_agent_modes$set(module_id, list(
    current_mode = new_mode,
    modes = agent_conf$modes,
    default_mode = agent_conf$parameters$default_mode
  ))
  bind_tools_for_mode(local_chat, session, new_mode)
})
```

#### `bind_tools_for_mode()` — Replaces `bind_tools_from_registry()`

```r
bind_tools_for_mode <- function(chat, sess, mode) {
  # ... look up entry from registry ...
  enabled_tools <- Filter(function(t) {
    is_tool_enabled_for_mode(t, mode)
  }, entry$tools)
  chat$set_tools(enabled_tools)
}
```

### 7c: Mode Enforcement on MCP Tool Calls

#### `mcp_handle_tools_call()` — Mode guard

After looking up `tool_obj` from `entry$tools`, before calling
`ellmer_tool_call()`:

```r
# Read current mode
globals <- get_shidashi_globals()
mode_entry <- globals$module_agent_modes$get(entry$shidashi_module_id)
current_mode <- if (!is.null(mode_entry)) mode_entry$current_mode

# Check permission
if (!is_tool_enabled_for_mode(tool_obj, current_mode)) {
  enabled_val <- tool_obj@annotations$shidashi_enabled
  allowed <- if (isTRUE(enabled_val)) "all modes"
             else paste(enabled_val, collapse = ", ")
  return(mcp_json_result(id, list(
    content = list(list(type = "text",
      text = paste0("Tool '", tool_name,
                    "' is not available in '", current_mode,
                    "' mode. Allowed: ", allowed))),
    isError = TRUE
  ), mcp_session_id))
}
```

#### `mcp_handle_tools_list()` — Mode-aware listing

Filter per-session tools by current mode before returning schema to
MCP clients. External clients only see tools available in the active
mode.

#### Skill script mode check (`R/skill-wrapper.R`)

In the `action="script"` branch, call
`tool@annotations$shidashi_get_mode()` and check
`is_script_enabled_for_mode()` before `run_skill_script()`.

### 7d: Built-in `ask_user` MCP Tool

#### Schema

```
name: "ask_user"
description: "Ask the application user a question and wait for their
  response. Use for confirmations, clarifications, or choices. Only
  available when bound to a Shiny session."
inputSchema:
  type: object
  properties:
    question: { type: string }
    choices:  { type: array, items: { type: string } }
    timeout_seconds: { type: integer, default: 60 }
  required: [question]
```

#### R implementation (`R/mcp-handler.R`)

Mirror the `shiny_query_ui` async pattern:

```r
mcp_tool_ask_user <- function(arguments, entry) {
  question <- arguments$question
  choices  <- arguments$choices
  timeout  <- arguments$timeout_seconds %||% 60L

  session  <- entry$shiny_session
  request_id <- rand_string()
  input_id <- paste0(entry$namespace, "-@ask_user_result@")

  session$sendCustomMessage("shidashi.ask_user", list(
    question   = question,
    choices    = choices,
    request_id = request_id,
    input_id   = input_id
  ))

  promises::promise(function(resolve, reject) {
    remaining <- as.integer(timeout * 2L)  # 500ms intervals
    check_fn <- function() {
      res <- shiny::isolate(session$input[["@ask_user_result@"]])
      if (!is.null(res) && identical(res$request_id, request_id)) {
        resolve(res$response)
      } else if (remaining <= 0L) {
        reject(simpleError("Timeout: user did not respond"))
      } else {
        remaining <<- remaining - 1L
        later::later(check_fn, 0.5)
      }
    }
    check_fn()
  })
}
```

#### JS handler (`src/index.js`)

Register `shidashi.ask_user`:
- Render inline prompt in chatbot area: question text + choice buttons
  (or text input if no choices)
- On response: `Shiny.setInputValue(params.input_id, { request_id, response }, { priority: "event" })`
- Auto-dismiss UI after response

#### CSS (`src/shidashi.scss`)

Minimal styles for `.shidashi-ask-user-prompt` container within the
chatbot drawer area.

### 7e: Destructive Category Auto-Confirmation

#### MCP tool calls (`mcp_handle_tools_call()`)

After mode check passes, before `ellmer_tool_call()`:

```r
if ("destructive" %in% tool_obj@annotations$shidashi_category) {
  confirm_result <- mcp_tool_ask_user(list(
    question = paste0("Tool '", tool_name, "' is marked as destructive. Proceed?"),
    choices = c("Proceed", "Stop and revise")
  ), entry)

  return(promises::then(confirm_result, function(response) {
    if (identical(response, "Proceed")) {
      result <- ellmer_tool_call(tool_obj, arguments, provider)
      if (promises::is.promise(result)) result else mcp_json_result(id, result, mcp_session_id)
    } else {
      mcp_json_result(id, list(
        content = list(list(type = "text", text = "Tool call cancelled by user.")),
        isError = TRUE
      ), mcp_session_id)
    }
  }))
}
```

#### Skill scripts

Before `run_skill_script()`, check script-level category for
`"destructive"`. Use session getter from annotation to invoke the
same confirmation pattern. Returns promise.

### 7f: Integration & Polish

- **Persist mode per conversation**: Extend conversation entry with
  `mode` field. On save: store current mode. On restore: switch mode
  selector to saved mode. On new conversation: reset to `default_mode`.

- **`npm run build`** after JS/SCSS changes.

### Files to Modify

| File | Changes |
|------|---------|
| `R/init-app.R` | Add `module_agent_modes` fastmap |
| `R/modules.R` | Store raw `enabled`, script configs, mode getter in annotations |
| `R/chatbot.R` | Mode selector UI, `bind_tools_for_mode()`, mode observer, helpers, conversation mode persistence |
| `R/mcp-handler.R` | Mode guard in `tools/call`, mode filter in `tools/list`, `ask_user` built-in tool, destructive wrapper |
| `R/skill-wrapper.R` | Script-level mode + destructive checks |
| `src/index.js` | `shidashi.ask_user` JS handler |
| `src/shidashi.scss` | `.shidashi-ask-user-prompt` styles |

### Deliverables

- [x] `module_agent_modes` in init-app globals
- [x] Raw `enabled` preservation in tool/skill annotations
- [x] `is_tool_enabled_for_mode()`, `is_script_enabled_for_mode()` helpers
- [x] Mode selector dropdown in chatbot header UI
- [x] Mode change observer + `bind_tools_for_mode()`
- [x] Mode guard in `mcp_handle_tools_call()`
- [x] Mode-aware `mcp_handle_tools_list()`
- [x] `ask_user` built-in MCP tool (R + JS)
- [x] Destructive auto-confirmation in MCP tool calls
- [x] Destructive auto-confirmation for skill scripts (via per-script category check)
- [x] Per-conversation mode persistence
- [x] `npm run build` for JS/SCSS assets
