# Changelog

## shidashi 0.2.1

- Added a color picker widget using vanilla `shiny` select input;
- Added base theme for plots and viewers that are registered output,
  such as `plotOutput2`;

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
