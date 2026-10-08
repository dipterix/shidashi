# Changelog

## shidashi 0.2.1

- The `MCP` endpoint keeps a call log for each running app in the cache
  folder, `MCP-logs/date-<start time>_app-<app id>/mcp-calls.log`: one
  line (at most 300 characters) per request, reply, or failure, with the
  tool, the `JSON-RPC` id, the time taken, and the arguments, result, or
  reason. The stdio proxy adds the calls that never reach an app, marked
  `(proxy)`. Turn the log off with `options(shidashi.mcp_log = FALSE)`
  or the environment variable `SHIDASHI_MCP_LOG=false`; the newest
  `getOption("shidashi.mcp_log_keep", 50)` folders are kept
- A running app writes `logs/server-info.log` in its folder (app id,
  process id, port, addresses, and call log folder). It and the app
  record are removed when the app stops, so an app stopped inside an R
  session that keeps running no longer leaves a record behind
- Until an app has answered it, the stdio proxy skips app records whose
  port refuses connections and tries the next newest, instead of failing
  every call on a stopped app
- [`register_input()`](https://dipterix.org/shidashi/reference/register_io.md)
  gains `hint` (one of `input_hint_classes`): whether agents ask the
  user for an input before loading data or running the analysis, keep
  its default, or leave it alone. `shiny_input_info` returns each
  input’s hint, takes a `hints` filter, and reports session state
  registered with the new
  [`register_input_state()`](https://dipterix.org/shidashi/reference/register_input_state.md)
  under `@state`
- With no browser page open, `switch_module` and module tool calls give
  the agent the app’s address as a one-click link
- The Claude plugin adds a `rave` skill: how agents find a running
  `RAVE` app, open it in the browser, and what to ask before loading
  data
- Added
  [`mcp_click()`](https://dipterix.org/shidashi/reference/mcp_click.md):
  clicks an element for an agent and reports whether it matched, was
  clicked, or was refused; the browser refuses elements inside
  `[mcp-agent-disabled="true"]` (controls for people only).
  `shiny_input_update` clicks buttons through it, so a refused or
  missing button now fails the tool call
- [`colormapSelectInput()`](https://dipterix.org/shidashi/reference/colormapSelectInput.md)
  can no longer be emptied: Backspace/Delete keep the selected color
  map, an update with an empty `selected` restores the previous value
  (or the first color map), and a `selected` outside the choices selects
  the first one
- Added a color picker widget using vanilla `shiny` select input;
- Added base theme for plots and viewers that are registered output,
  such as `plotOutput2`;
- Redesigned the `MCP` endpoint so agents such as `Claude Code` can
  drive the dashboard without session binding:
  - the tool list is built from the template on disk (each module’s
    tools load once without a browser), so it is available before any
    browser opens and never changes while an agent is connected; tools
    from modules that fail to load fall back to
    `agents/tool-schema.yaml`
  - each tool call runs in a module chosen on the spot: the module named
    by the optional `_module` argument, else the module tab the user
    pinned with the new pin button, else the one the user used most
    recently; results end with a note naming the module
  - removed the `list_shinysessions`, `register_shinysession`,
    `get_session_info`, and `ask_user` `MCP` tools; added
    `shidashi_sessions` (open modules and the default one) and
    `shidashi_call` (tools that exist only in live sessions)
  - the server no longer issues `Mcp-Session-Id`; `/mcp/{module}` limits
    a connection to one module (a module id or a handle)
  - agent modes and the confirmation policy apply only to the
    in-dashboard chat; over `MCP`, tools carry `readOnlyHint` and
    `destructiveHint` annotations and a note, and the agent asks the
    user in its own chat, never in the browser; tools turned off in
    `agents.yaml` stay off
  - the stdio proxy picks up apps from per-app records, follows an app
    across restarts, accepts `--app` and `--module`, and always replies
    to a request
  - the stdio proxy works without a running app: it connects, lists the
    tools it can, and tells the agent to ask the user whether to start
    an app or launch a saved one
  - the stdio proxy can attach to a shidashi app at any address for the
    current session (`shidashi_connect`, `shidashi_disconnect`); its
    tool list follows the attached app, and `shidashi_tools` lists the
    app’s tools for clients that do not refresh their tool list
  - module handles always carry the session token prefix
    (`<module>@<token>`), so a handle stays the same when the user opens
    the module again in another tab
  - added the `switch_module` meta tool: it shows a module in the user’s
    dashboard as clicking it in the sidebar does (its open tab comes to
    the front, or it opens in a new tab; `auto_new = FALSE` only
    switches to an open tab), and returns once the module’s page has
    loaded (options `shidashi.switch_module_timeout` and
    `shidashi.switch_module_wait`); it is refused while the user has a
    module pinned
  - the dashboard now finds a module’s open tab by its module id, and a
    module page asks its dashboard directly when switching modules, so
    [`switch_module()`](https://dipterix.org/shidashi/reference/module_info.md)
    also works when the dashboard sits in a frame
  - [`switch_module()`](https://dipterix.org/shidashi/reference/module_info.md)
    gains `auto_new`: with `auto_new = FALSE` it only switches to a
    module whose tab is open
  - exported
    [`mcp_call_active()`](https://dipterix.org/shidashi/reference/mcp_call_active.md):
    it is `TRUE` while a tool runs for an `MCP` call, and while it is,
    the environment variable `SHIDASHI_USING_MCP` is `"TRUE"` (removed
    when the call returns), so tools and skill scripts can behave
    differently for agents, for example print less
- Each skill is now two tools: `skill_load__<name>` reads the
  instructions and reference files and never changes anything, and
  `skill_run__<name>` runs the scripts;
  [`skill_wrapper()`](https://dipterix.org/shidashi/reference/skill_wrapper.md)
  returns both (`load`, `run`); in the dashboard chat, a script marked
  destructive in `agents.yaml` now asks for confirmation
- Skill scripts document their arguments in a `# Usage:` header comment;
  `skill_run__<name>` lists each script’s usage and refuses a call that
  leaves out a required argument; files in `scripts/` whose names start
  with `_` are helpers, not scripts
- Environment variables passed to a skill script (`envs`) are now added
  to the app’s environment instead of replacing it, so the script keeps
  `PATH`, `HOME`, and `SHIDASHI_USING_MCP`
- Added
  [`save_launcher()`](https://dipterix.org/shidashi/reference/save_launcher.md)
  and
  [`run_launcher()`](https://dipterix.org/shidashi/reference/save_launcher.md):
  saved apps are kept in one `launchers.json` file in the `shidashi`
  cache folder, optionally with a copy of the app (`copy_app = TRUE`)
  and free-form metadata; the `MCP` proxy lists saved apps
  (`shidashi_launchers`) and, when the user picks one, starts it and
  opens the chosen module in the browser (`shidashi_launch`)
- `shiny_query_ui` now returns the element’s HTML or image in one call;
  `shiny_query_ui_result` is removed; `transform_image = FALSE` asks for
  HTML only, and long HTML is trimmed (image data and scripts shortened,
  `max_chars` sets the limit)
- Added the `shiny_output_result` `MCP` tool: it returns a registered
  output’s rendered content even when the output is in a hidden tab or a
  collapsed card, rendering it first (waiting up to 10 seconds; option
  `shidashi.output_result_timeout`); a plot that was never shown is
  drawn at a fallback size; `shiny_query_ui` notes when an element is
  not shown or shows an error; outputs registered with
  `download_type = "htmlwidget"` also return the widget data (`x`),
  since a widget such as a `DT` table shows only one page of it, and
  outputs registered with `download_type = "data"` also return what
  `download_function` writes; both are trimmed by `max_chars`
- Added
  [`render_hidden_output()`](https://dipterix.org/shidashi/reference/render_hidden_output.md),
  which renders one output at the next flush even when it is hidden,
  then restores `suspendWhenHidden`
- `shiny_query_ui` and `shiny_output_result` ask the browser after a
  short pause (option `shidashi.query_ui_delay`, default 0.1 seconds):
  agents often send a change and a query in one turn as concurrent
  requests, which `R` may take in either order, and the pause lets the
  change reach the page first
- In the `bslib-bare` template, `shiny_query_ui` and
  `shiny_output_result` ask a `threeBrain` viewer for pictures of its
  `WebGL` or `WebGPU` canvases: they dispatch one
  `viewerApp.captureOnce` event on the viewer’s wrapper
  (`.threejs-brain-canvas`) with an empty object as `detail`, and the
  viewer draws a frame and adds `{ canvas, dataURI }` to `detail.views`
  for each view it drew. When the viewer has not answered after three
  animation frames, and for any other canvas, the canvas is read
  directly as before. Such canvases used to come back blank in
  `Chromium`, or out of date in browsers that keep the last frame. A
  page that draws no frames (for example in a background tab) is read
  after half a second, with a note
- Errors inside `shidashi`’s own observers are reported as warnings
  instead of ending the user’s session
- [`register_input()`](https://dipterix.org/shidashi/reference/register_io.md)
  gains `tooltip`, shown when the mouse hovers over the input (its
  `title`); it defaults to the first sentence of `description` (new
  [`as_tooltip()`](https://dipterix.org/shidashi/reference/register_io.md)),
  and `tooltip = NULL` turns it off; only inputs get it, so other
  registered elements, such as cards, are unchanged

## shidashi 0.2.0

CRAN release: 2026-04-10

### New Features

- Added `stream_viz` `htmlwidgets` widget for real-time multi-channel
  signal viewing; binary stream files are produced by
  [`stream_to_js()`](https://dipterix.org/shidashi/reference/stream_to_js.md)
  and fetched by the browser via `fetchStreamData()`; rendering engine
  switched from `D3` to `Three.js` (`WebGL`) for improved performance on
  high-density multi-channel data
- Added streaming helpers:
  [`stream_init()`](https://dipterix.org/shidashi/reference/stream_init.md)
  sets up per-session stream directories with automatic cleanup;
  [`stream_path()`](https://dipterix.org/shidashi/reference/stream_path.md)
  returns the token-qualified file path;
  [`stream_file_id()`](https://dipterix.org/shidashi/reference/stream_file_id.md)
  builds the `{token}_{ns(id)}` identifier used by both R and `JS`
- Added
  [`stream_to_js()`](https://dipterix.org/shidashi/reference/stream_to_js.md)
  for writing binary envelope files (supports `raw`, `json`, `int32`,
  `float32`, `float64` body types) and
  [`read_stream_vis()`](https://dipterix.org/shidashi/reference/read_stream_vis.md)
  for reading them back in R
- Added
  [`streamVizOutput()`](https://dipterix.org/shidashi/reference/streamVizOutput.md)
  /
  [`renderStreamViz()`](https://dipterix.org/shidashi/reference/renderStreamViz.md)
  /
  [`updateStreamViz()`](https://dipterix.org/shidashi/reference/updateStreamViz.md)
  Shiny bindings for the `stream_viz` widget
- [`register_output()`](https://dipterix.org/shidashi/reference/register_io.md)
  is now a server-side function: it assigns the render function,
  registers the `MCP` output spec, and injects download/pop-out widget
  icons via `JS` overlay (no UI-side wrapper needed)
- Added output widget overlay system: registered outputs gain
  hover-visible download and pop-out icons injected entirely by `JS`;
  download modal supports `image`, `htmlwidget`, `threeBrain`, `data`,
  and `stream_viz` types
- Added
  [`server_standalone_viewer()`](https://dipterix.org/shidashi/reference/server_standalone_viewer.md)
  — a hidden module that re-renders a parent session’s output in a
  standalone browser tab (pop-out window), forwarding inputs back to the
  original module session
- Added
  [`fire_event()`](https://dipterix.org/shidashi/reference/fire_event.md)
  and
  [`get_event()`](https://dipterix.org/shidashi/reference/fire_event.md)
  for a reactive session event bus; events can be scoped locally
  (per-session) or globally (cross-tab broadcast via `shared_id`);
  [`get_theme()`](https://dipterix.org/shidashi/reference/fire_event.md)
  is a convenience wrapper that returns the current dashboard theme
- Added
  [`register_session()`](https://dipterix.org/shidashi/reference/register_session.md)
  /
  [`unregister_session()`](https://dipterix.org/shidashi/reference/register_session.md)
  for comprehensive session life-cycle management with automatic
  cleanup, reactive event bus setup, and cross-tab synchronization
  support; replaces the deprecated `register_session_id()`
- Added
  [`get_handler()`](https://dipterix.org/shidashi/reference/register_session.md)
  /
  [`set_handler()`](https://dipterix.org/shidashi/reference/register_session.md)
  for managing named session-scoped `Observer` objects with a shared
  registry; handlers are automatically destroyed on session end
- Added
  [`enable_input_broadcast()`](https://dipterix.org/shidashi/reference/register_session.md)
  /
  [`disable_input_broadcast()`](https://dipterix.org/shidashi/reference/register_session.md)
  and
  [`enable_input_sync()`](https://dipterix.org/shidashi/reference/register_session.md)
  /
  [`disable_input_sync()`](https://dipterix.org/shidashi/reference/register_session.md)
  for opt-in cross-tab input state synchronization; broadcast publishes
  the current session’s inputs for peer tabs, sync restores inputs from
  a peer session
- Added
  [`switch_module()`](https://dipterix.org/shidashi/reference/module_info.md)
  to programmatically navigate to another module from server-side code;
  supports cross-`iframe` forwarding via `JS` `postMessage`
- Added
  [`card_badge()`](https://dipterix.org/shidashi/reference/card_badge.md)
  UI component for dynamic badge widgets in card headers;
  [`set_card_badge()`](https://dipterix.org/shidashi/reference/card_badge.md)
  updates badge text and styling from the server without re-rendering;
  [`card_recalculate_badge()`](https://dipterix.org/shidashi/reference/card_badge.md)
  creates a clickable “recalculate needed” badge with
  [`enable_recalculate_badge()`](https://dipterix.org/shidashi/reference/card_badge.md)
  /
  [`disable_recalculate_badge()`](https://dipterix.org/shidashi/reference/card_badge.md)
  toggles
- Added
  [`html_asis()`](https://dipterix.org/shidashi/reference/html_asis.md)
  for escaping HTML special characters to display strings literally;
  [`combine_html_class()`](https://dipterix.org/shidashi/reference/html_class.md)
  merges and remove duplicated class strings;
  [`remove_html_class()`](https://dipterix.org/shidashi/reference/html_class.md)
  removes specified classes from a class string
- `shared_id` is now unified and shared across UI and server via
  [`init_app()`](https://dipterix.org/shidashi/reference/init_app.md);
  resolved from URL query string, R option, environment variable, or
  auto-generated
- Internal session registries (`tools`, `output_renderers`, `handlers`)
  now use `fastmap` for `O(1)` lookup and efficient memory management
- Added `_captureSVG()` helper in `JS` to convert `SVG` (raster)
  elements (e.g. `D3` output) to `PNG` data URLs for the query-UI tool
- Added `shidashi.set_shiny_input` `JS` message handler for programmatic
  cross-session input forwarding
- Added `shidashi.switch_module` `JS` message handler for programmatic
  module navigation from `JS`
- Added `shidashi.register_output_widgets` `JS` message handler that
  injects the download/pop-out overlay icons on registered outputs
- Added demo template modules: `output_widgets`, `stream_viz`, and
  `session_events`; added hidden `standalone_viewer` module
- Added `htmlwidgets` to `Imports`

### Bug Fixes

- Fixed download file extension not used correctly in
  [`register_output()`](https://dipterix.org/shidashi/reference/register_io.md)
- Fixed position issue for output widget overlay container
- Fixed multi-result `MCP` tool request not handled correctly in
  chat-bot
- Sanitized `MCP` tool-call results for dashboard display

## shidashi 0.1.7 & 0.1.8

### New Features

- Added built-in AI chat-bot panel powered by `ellmer` and `shinychat`;
  supports multiple providers, in-memory conversation history,
  mode-based tool permissions, token/cost display, and early-stop
  controls
- Added
  [`init_chat()`](https://dipterix.org/shidashi/reference/init_chat.md)
  to create an `ellmer` `Chat` object from R options
  (`shidashi.chat_provider`, `shidashi.chat_model`,
  `shidashi.chat_system_prompt`, `shidashi.chat_base_url`)
- Added `MCP` (Model Context Protocol) proxy server (`inst/mcp-proxy/`)
  so external `LLM` clients can interact with a running Shiny
  application via `MCP`
- Added
  [`mcp_wrapper()`](https://dipterix.org/shidashi/reference/mcp_wrapper.md)
  to register an `MCP` endpoint for a Shiny module
- Added
  [`register_input()`](https://dipterix.org/shidashi/reference/register_io.md)
  /
  [`register_output()`](https://dipterix.org/shidashi/reference/register_io.md)
  helpers to expose Shiny inputs and outputs as `MCP` tool parameters
  with descriptions
- Added skills system:
  [`skill_wrapper()`](https://dipterix.org/shidashi/reference/skill_wrapper.md)
  parses and runs reusable agent skill scripts; skill working directory
  is resolved relative to the skill folder
- Tools and skills are now category- and permission-aware; module IDs
  are excluded from tool names for consistency
- Added
  [`module_drawer()`](https://dipterix.org/shidashi/reference/module_drawer.md),
  [`drawer_open()`](https://dipterix.org/shidashi/reference/drawer.md),
  [`drawer_close()`](https://dipterix.org/shidashi/reference/drawer.md),
  and
  [`drawer_toggle()`](https://dipterix.org/shidashi/reference/drawer.md)
  for controlling a slide-in drawer panel
- [`module_info()`](https://dipterix.org/shidashi/reference/module_info.md)
  now returns richer per-module metadata; added
  [`current_module()`](https://dipterix.org/shidashi/reference/module_info.md)
  and
  [`active_module()`](https://dipterix.org/shidashi/reference/module_info.md)
  helpers for querying the active Shiny module
- Modules support an optional `agents.yaml` for declaring agent
  configurations (tools, skills, auto-approve rules)
- `MCP` host can be a remote server; fuzzy module reference is supported
  when resolving module IDs
- Added demo template modules: `aiagent`, `filestructure`, and
  `mcpsetup`
- Added `ellmer` content helpers: S7 generic `ellmer_as_json()` for
  `ContentText`, `ContentImageInline`, `ContentImageRemote`, and
  `ContentToolResult`; and `content_to_mcp()` for converting chat
  content to `MCP` responses
- Chat-bot UI displays token usage and API cost next to each turn

### Bug Fixes

- Fixed images not being passed correctly to the agent
- Fixed sidebar start-collapsed behavior
- Fixed bare-bone template initial setup
- Fixed `MCP` server query-UI tool response
- Fixed permission issue when executing skill scripts
- Applied `npm audit fix` to bundled `JavaScript` dependencies

## shidashi 0.1.6

CRAN release: 2024-02-17

- Load scripts starting with `shared-` when loading modules

## shidashi 0.1.5

CRAN release: 2023-04-04

- Fixed `accordion` and `card_tabset` not working properly when
  `inputId` starts with digits
- Updated templates and used `npm` to compile
- Session information now stores at `userData` instead of risky `cache`
- Ensured at least template root directory is available

## shidashi 0.1.4

CRAN release: 2022-10-15

- Fixed a bug that makes application fail to launch on `Windows`
- Added support to evaluated expressions before launching the
  application, allowing actions such as setting global options and
  loading data

## shidashi 0.1.3

CRAN release: 2022-08-06

- Allow modules to be hidden from the sidebar

## shidashi 0.1.2

CRAN release: 2022-06-21

- Fixed group name not handled correctly as factors
- Module `URL` respects domain now and is generated with relative path
- Works on `rstudio-server` now
- More stable behavior to `flex_container`
- Allow output (mainly plot and text outputs) to be reset
- Fixed `iframe` height not set correctly
- Enhanced 500 page to print out `traceback`, helping debug the errors
- Added `flex_break` to allow wrapping elements in flex container
- Added `remove_class` to remove `HTML` class from a string
- Allow to set `data-title` to cards

## shidashi 0.1.0

CRAN release: 2021-11-17

- Added a `NEWS.md` file to track changes to the package.
