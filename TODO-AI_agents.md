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
