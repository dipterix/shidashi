# shidashi 0.1.7 & 0.1.8

## New Features

* Added built-in AI chat-bot panel powered by `ellmer` and `shinychat`; supports
  multiple providers, in-memory conversation history, mode-based tool 
  permissions, token/cost display, and early-stop controls
* Added `init_chat()` to create an `ellmer` `Chat` object from R options
  (`shidashi.chat_provider`, `shidashi.chat_model`, `shidashi.chat_system_prompt`,
  `shidashi.chat_base_url`)
* Added `MCP` (Model Context Protocol) proxy server (`inst/mcp-proxy/`) so 
  external `LLM` clients can interact with a running Shiny application via `MCP`
* Added `mcp_wrapper()` to register an `MCP` endpoint for a Shiny module
* Added `register_input()` / `register_output()` helpers to expose Shiny inputs
  and outputs as `MCP` tool parameters with descriptions
* Added skills system: `skill_wrapper()` parses and runs reusable agent skill
  scripts; skill working directory is resolved relative to the skill folder
* Tools and skills are now category- and permission-aware; module IDs are excluded
  from tool names for consistency
* Added `module_drawer()`, `drawer_open()`, `drawer_close()`, and
  `drawer_toggle()` for controlling a slide-in drawer panel
* `module_info()` now returns richer per-module metadata; added `current_module()`
  and `active_module()` helpers for querying the active Shiny module
* Modules support an optional `agents.yaml` for declaring agent configurations
  (tools, skills, auto-approve rules)
* `MCP` host can be a remote server; fuzzy module reference is supported when
  resolving module IDs
* Added demo template modules: `aiagent`, `filestructure`, and `mcpsetup`
* Added `ellmer` content helpers: S7 generic `ellmer_as_json()` for `ContentText`,
  `ContentImageInline`, `ContentImageRemote`, and `ContentToolResult`; and
  `content_to_mcp()` for converting chat content to `MCP` responses
* Chat-bot UI displays token usage and API cost next to each turn

## Bug Fixes

* Fixed images not being passed correctly to the agent
* Fixed sidebar start-collapsed behavior
* Fixed bare-bone template initial setup
* Fixed `MCP` server query-UI tool response
* Fixed permission issue when executing skill scripts
* Applied `npm audit fix` to bundled `JavaScript` dependencies

# shidashi 0.1.6

* Load scripts starting with `shared-` when loading modules

# shidashi 0.1.5

* Fixed `accordion` and `card_tabset` not working properly when `inputId` starts with digits
* Updated templates and used `npm` to compile
* Session information now stores at `userData` instead of risky `cache`
* Ensured at least template root directory is available

# shidashi 0.1.4

* Fixed a bug that makes application fail to launch on `Windows`
* Added support to evaluated expressions before launching the application, allowing actions such as setting global options and loading data


# shidashi 0.1.3

* Allow modules to be hidden from the sidebar

# shidashi 0.1.2

* Fixed group name not handled correctly as factors
* Module `URL` respects domain now and is generated with relative path
* Works on `rstudio-server` now
* More stable behavior to `flex_container`
* Allow output (mainly plot and text outputs) to be reset
* Fixed `iframe` height not set correctly
* Enhanced 500 page to print out `traceback`, helping debug the errors
* Added `flex_break` to allow wrapping elements in flex container
* Added `remove_class` to remove `HTML` class from a string
* Allow to set `data-title` to cards

# shidashi 0.1.0

* Added a `NEWS.md` file to track changes to the package.
