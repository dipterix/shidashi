# Plan: Unified Session Registry with Event Bus

## TL;DR

Rename `register_session_mcp` → `register_session`, unify the MCP session registry into a general session registry, extend entries with `shared_id` + `events` fields, move generic session helpers to `globals.R`, and add event bus helpers. Later phases rewire `register_global_reactiveValues` and wire event dispatch.

## Phase 1: Rename + Extend + Move

### Step 1: Rename registry in `init_app()` (R/globals.R L57)

- `global_env$mcp_session_registry` → `global_env$session_registry`

### Step 2: Rename accessor (R/globals.R L121)

- `globals_mcp_session_registry()` → `globals_session_registry()` — update error message to drop "MCP"

### Step 3: Move generic session helpers from mcp-handler.R → globals.R

Move these definitions, renaming as they move:

- `register_session_mcp()` → `register_session()`
- `mcp_unregister_session()` → `unregister_session()`
- `mcp_sweep_closed_sessions()` → `sweep_closed_sessions()`
- `mcp_get_shiny_entry()` → `get_session_entry()`

### Step 4: Extend entry structure and auto-resolve `shared_id`

Add new fields to the entry created in `register_session()`:

```
shared_id        = <auto-resolved>,
events           = shiny::reactiveValues()
```

Auto-resolve `shared_id` in `register_session()` using the same logic as `register_session_id()`:
1. If entry already exists with a `shared_id`, keep it
2. Else parse `?shared_id=...` from `session$clientData$url_search` (already captured as `url`)
3. Fallback: generate random lowercase 26-char string via `rand_string()`

This is safe because `register_session()` runs first (injected at top of module server in `modules.R`), before user code calls `register_session_id()`. If `register_session_id()` is later called with an explicit `shared_id`, it can update the entry.

### Step 5: Update all callers (~44 references)

| File | Lines | Change |
|------|-------|--------|
| R/globals.R | 295 | `globals_mcp_session_registry()` → `globals_session_registry()` |
| R/modules.R | 328-329 | `register_session_mcp` → `register_session`, `globals_mcp_session_registry` → `globals_session_registry` |
| R/mcp-handler.R | 8 accessor refs + self-calls | All `globals_mcp_session_registry()` → `globals_session_registry()`, plus renamed helpers in `onSessionEnded` callback and sweep calls |
| R/mcp-wrapper.R | 1093 | `mcp_get_shiny_entry` → `get_session_entry` |
| R/standalone-viewer.R | 32 | `mcp_get_shiny_entry` → `get_session_entry` |

### Step 6: Keep MCP-specific helpers in mcp-handler.R (no rename)

- `mcp_tool_bound_shinysessions()` — stays, update internal accessor call
- `mcp_tool_unregister_shinysession()` — stays, update internal accessor call

## Phase 2: Event bus helpers (globals.R)

- `globals_get_shared_id(session)` — returns shared_id from entry
- `globals_get_sessions_by_shared_id(shared_id)` — returns list of live entries
- `globals_fire_event(key, value, session, global = FALSE)` — sets event; if global, propagates to same shared_id
- `globals_get_event(key, session)` — reactive read

## Phase 3: Rewire shared-session.R

- Rewire `register_global_reactiveValues()` to use registry's events
- Call `register_session()` + set `shared_id` in `register_session_id()` after shared_id resolution
- Replace all `private_id` reads/writes with `session$token` (eliminates `session$userData$shidashi$private_id`)
- Keep `input_reactives`, `input_sync_handler`, `broadcast_observer`, `event_data`, `event_handler` in `session$userData$shidashi$*` for now — too many coupled changes to move in one shot

## Verification

1. `devtools::load_all()` — no errors
2. `grep -rn "mcp_session_registry\|register_session_mcp\|mcp_unregister_session\|mcp_sweep_closed\|mcp_get_shiny_entry" R/` — only the two kept MCP-specific helpers should have `mcp_` prefix
3. `devtools::test()`
4. Smoke test: `create_barebone_bslib(tmp); render(root_path = tmp)`

## Decisions

- **Unified registry** — no separate `session_registry` vs `mcp_session_registry`
- Generic helpers → `globals.R`; MCP-specific (`mcp_tool_bound_*`) → stay in `mcp-handler.R`
- New entry fields: `shared_id` auto-resolved from URL on registration (fallback: random string), `events` initialized as `shiny::reactiveValues()` immediately
- `private_id` replaced by `session$token` — no need to store separately (Phase 3)
- `input_reactives`, `input_sync_handler`, `broadcast_observer`, `event_data`, `event_handler` stay in `session$userData$shidashi$*` for now
- All renamed functions are internal — no backward-compat aliases needed
