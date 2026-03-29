# TODO: `register_output` Refactor Plan

## Goal

Refactor `register_output()` from a UI-side wrapper into a **server-side** function that:

1. Assigns render functions to `session$output`
2. Registers MCP output specs
3. Sets up download/popout widget handlers (via an internal helper `register_output_widgets`)
4. The UI overlay (download/popout icons) is done **entirely via JS** — no R-side UI wrapper function needed

## Current State

- `register_output(expr, outputId, description, quoted, env)` — UI-side; `expr` is a call like `plotOutput(ns("x"))`. Evaluates it and registers MCP spec. ([R/mcp-wrapper.R](R/mcp-wrapper.R) ~L898)
- `register_output_spec` closure inside `mcp_wrapper_input_output()` — stores spec in `output_specs` fastmap, evals the UI expr. ([R/mcp-wrapper.R](R/mcp-wrapper.R) ~L351)
- `.register_output` binding injected into module env via `mcp_wrapper_input_output()` return value. ([R/modules.R](R/modules.R) ~L271)
- Demo module calls `register_output(plotOutput(ns("iris_plot"), ...), ...)` in UI function.

## New Design

### New `register_output` Signature (exported)

```r
register_output(
  expr,           # e.g. renderPlot({...}) — a render function call, server-side
  outputId,       # character: the output ID (unnamespaced)
  description = "", # served as both mcp description for outputs and download widget title
  quoted = FALSE,
  env = parent.frame(),
  ...,
  output_opts = list(),     # extra options for the output (width, height defaults, etc.)
  download_function = NULL, # custom download handler; NULL = auto-detect from download_type
  download_type = "image",    # "image", "threeBrain", "data", "no-download"
  extensions = NULL,        # allowed file extensions for download
  session = shiny::getDefaultReactiveDomain()
)
```

**Key**: `expr` is now something like `renderPlot({...})` — a render function call used on the server side. The parameter name stays `expr` for compatibility with the existing closure pattern.

### How It Works

1. **Substitute `expr`** if `!quoted`, same as before.
2. ~~**Evaluate `expr`** in `env` → this yields the render function object (e.g., the result of `renderPlot({...})`).~~ (see step 6)
3. **`find_expr(expr)`**: Parse the render function call (e.g. `renderPlot({plot(iris)})`) to extract the `expr` argument. This is needed so 
  - see 4 below
  - the download handler can re-evaluate the plotting expression into a graphics device.
4. **Register MCP spec**: Call `.register_output` (the closure from `mcp_wrapper_input_output`) if available; pass `expr` and `quoted=TRUE` to store the expression so AI agents know the implementation. However, do not evaluate the `expr` in register_output_spec - it simply records the implementation
5. **Call `register_output_widgets()`** (internal helper) to set up download handler, popout handler, and send output metadata to the JS side.
6. **Assign** evaluate `expr` in `env` to obtain `render_function`, then `session$output[[outputId]] <- render_function` — standard Shiny server-side output assignment.

### `register_output_widgets()` — Internal Server-Side Helper (NOT exported)

This is the core implementation function. It is called by `register_output()` and handles:

- Previously **`find_expr(expr)`** have already parsed the render function call (e.g. `renderPlot({plot(iris)})`) to extract the `expr` argument (e.g. `{plot(iris)}`). The expr is passed to register_output_widgets(expr, ...): This is needed so the download handler can re-evaluate the plotting expression into a graphics device.
- **Download handler**: Based on `download_type`:
  - `"image"`: Re-evaluate `expr` inside `png()`/`pdf()`/`svg()` device; use `downloadHandler`. Modal asks for width (30cm default), height (from current aspect ratio, rounded to 0.1cm), filename (outputId + timestamp)
  - `"threeBrain"`: Call `asNamespace("threeBrain")$save_brain()`. Modal asks for filename and title (default "RAVE Viewer")
  - `"data"`: Use `download_function` provided by user. Modal asks for filename only
  - `"no-download"`: Skip download setup entirely
- **Send output metadata to JS**: Send a custom message to the client declaring this `outputId` as a registered output with its widget capabilities (download, popout). JS uses this to inject overlay icons. The icons are displayed with absolute positions and are placed at top-left
- **Store parsed render info**: Keep `render_expr` and `render_env` for standalone viewer use later. This can be stored in the registry (`globals_mcp_session_registry()`), into `output_renderers` entry along with the `output_opts` and `extensions` wrapped in a list

### `register_output_spec` Closure Update

Remove `eval` from `register_output_spec` inside `mcp_wrapper_input_output()` (~L369):

```r
register_output_spec <- function(expr, outputId, description = "", quoted = FALSE, env = parent.frame()) {
  ... 
  output_specs$set(outputId, item)

  return(invisible(item))
}
```

This lets `register_output()` call `.register_output(expr, outputId, description, ...)` without evaluating `expr`.

### JS-Side UI Overlay

Instead of ravedash's R-side `output_gadget_container()` (ravedash), the widget overlay icons are injected entirely by JS:

1. `register_output()` sends a Shiny custom message (e.g. `shidashi.register_output_widgets`) to the client with:
   - `outputId` (namespaced via `session$ns(outoutId)`)
   - `widgets`: list of enabled widgets (`"download"`, `"popout"`)
   - `download_type`
2. JS handler in `index.js` receives this message and:
   - Finds the output container element (by Shiny's output binding ID)
   - Wraps it with `position: absolute` wrapper div (class `shidashi-output-widget-wrapper`) positioned absolute top-left
   - Injects overlay icons (download, popout) into the container
   - Download icon click → sets Shiny input `{ns(outputId)}__download_trigger` which triggers the server-side download modal
   - Call `Shiny.bindAll` on the container to register the shiny-reactive events
   - Register popout icon js event: click → `window.open()` to standalone viewer URL

**Advantages over R-side UI wrapper**:
- No need for a separate UI function call
- Works with any output, including those generated dynamically
- Module authors only call `register_output()` in server — no paired UI registration needed
- Keeps UI code clean: just `plotOutput(ns("x"))` in UI

### SCSS Styles Needed

In `inst/builtin-templates/bslib-bare/src/shidashi.scss`:
- `.shidashi-output-widget-wrapper`: `position: relative`
- `.shidashi-output-widget-container`: `position: absolute; top: 0.25rem; left: 0.25rem; z-index: 10; display: flex; gap: 0.15rem; opacity: 0.5; transition: opacity 0.2s`
- `.shidashi-output-widget-wrapper:hover .shidashi-output-widget-container`: `opacity: 1`
- `.shidashi-output-widget-icon`: subtle button styling, dark-mode support

## Phases

### Phase 1: R — `register_output_spec` closure + `find_expr` + `register_output_widgets`

**Files**: [R/mcp-wrapper.R](R/mcp-wrapper.R)

1. **`register_output_spec` closure** (~L351): Remove `eval(expr, envir = env)`. Store `deparse1(expr)` in spec `type` column (like `register_input_spec` does). Return `invisible(item)`.
2. **`find_expr(call)`**: Local helper function (not exported). Takes a quoted render call (e.g. `renderPlot({plot(iris)})`), uses `match.call()` against the render function to extract the `expr` argument and `env`/`envir` argument. Must handle `::` prefix (e.g. `shiny::renderPlot(...)`) by resolving via `getExportedValue()`. Returns `list(expr = <inner_expr>, env = <env_or_NULL>)`.
3. **`register_output_widgets()`**: Internal helper (not exported). Signature: `register_output_widgets(render_expr, render_env, outputId, download_type, download_function, output_opts, extensions, description, session)`. Does:
   - Download handler setup based on `download_type` (`"image"` → graphics device re-eval; `"threeBrain"` → `asNamespace("threeBrain")$save_brain()`; `"data"` → user-supplied `download_function`; `"no-download"` → skip)
   - `shiny::bindEvent(shiny::observe({...(show modal)}), input[[paste0(outputId, "__download_trigger")]], ignoreNULL = TRUE, ignoreInit = TRUE)` → show download modal with fields depending on `download_type`:
     - `"image"`: width (numericInput, default 30 cm), height (numericInput, default based on current image aspect ratio rounded to 0.1 cm), filename (textInput, default `outputId_timestamp`)
     - `"threeBrain"`: filename (textInput), title (textInput, default "RAVE Viewer") — passed to `threeBrain::save_brain()`
     - `"data"`: filename (textInput) only
   - `session$output[[paste0(outputId, "__download")]] <- downloadHandler(...)` for the actual download
   - Send `session$sendCustomMessage("shidashi.register_output_widgets", ...)` with `outputId` (namespaced), enabled widgets, `download_type`
   - Store render info in `mcp_get_shiny_entry(session$token)$output_renderers$set(outputId, list(render_expr, render_env, output_opts, extensions))` <- FIXME: namedlist

### Phase 2: R — Rewrite exported `register_output()`

**Files**: [R/mcp-wrapper.R](R/mcp-wrapper.R)

1. **New signature**: `register_output(expr, outputId, description, quoted, env, ..., output_opts, download_function, download_type, extensions, session)`
2. **Body**:
   a. `if (!quoted) expr <- substitute(expr)`
   b. `parsed <- find_expr(expr)` — extract inner expr (with `renderXX` stripped) and env
   c. Look up `.register_output` impl via `get0()` (same pattern as current). If found, call `.register_output(expr = expr, outputId = outputId, description = description, quoted = TRUE, env = env)` — records raw call in MCP spec, does NOT eval (see phase 1)
   d. `register_output_widgets(render_expr = parsed$expr, render_env = parsed$env %||% env, outputId = outputId, download_type = download_type, download_function = download_function, output_opts = output_opts, extensions = extensions, description = description, session = session)`
   e. `render_function <- eval(expr, envir = env)` — evaluate the full `renderPlot({...})` call
   f. `session$output[[outputId]] <- render_function`
3. **Documentation**: Update `@rdname register_io` roxygen — new params, new examples showing server-side usage
4. **Fallback when `.register_output` not found**: Still eval `expr` and assign to `session$output` (works outside shidashi module env, just no MCP spec or widgets)

### Phase 3: JS — Widget Overlay Handler

**Files**: [inst/builtin-templates/bslib-bare/src/index.js](inst/builtin-templates/bslib-bare/src/index.js)

1. Add `Shiny.addCustomMessageHandler("shidashi.register_output_widgets", ...)` 
2. Handler receives `{outputId, widgets, download_type}`. Finds the output container by `id` attribute matching `outputId`
3. Adds `shidashi-output-widget-wrapper` class to the output's parent (sets `position: relative`)
   - return and do nothing if the wrapper already exists to prevent unnecessary double-initialization
4. Creates overlay div (`shidashi-output-widget-container`) positioned absolute top-left, inserts icon elements:
   - Download icon: `<a>` with download icon, on click → `Shiny.setInputValue(outputId + "__download_trigger", Date.now(), {priority: "event"})`
   - Popout icon: `<a>` with external-link icon, on click → `window.open()` (placeholder URL until Phase 6)
5. Call `Shiny.bindAll` on `shidashi-output-widget-wrapper` element

### Phase 4: SCSS — Widget Overlay Styles + Build

**Files**: [inst/builtin-templates/bslib-bare/src/shidashi.scss](inst/builtin-templates/bslib-bare/src/shidashi.scss)

1. `.shidashi-output-widget-wrapper` — `position: relative`
2. `.shidashi-output-widget-container` — `position: absolute; top: 0.25rem; left: 0.25rem; z-index: 10; display: flex; gap: 0.15rem; opacity: 0.5; transition: opacity 0.2s`
3. `.shidashi-output-widget-wrapper:hover .shidashi-output-widget-container` — `opacity: 1`
4. `.shidashi-output-widget-icon` — subtle button styling (small, semi-transparent bg), dark-mode support
5. Run `npm run build`

### Phase 5: Demo Module Update

**Files**: `inst/builtin-templates/bslib-bare/modules/demo/`

1. **UI** (`R/demo-ui.R`): Remove the old `register_output(plotOutput(ns("iris_plot"), ...), ...)` call. Replace with plain `plotOutput(ns("iris_plot"), height = "100%")`
2. **Server** (`server.R`): Add `shidashi::register_output(renderPlot({...}), outputId = "iris_plot", download_type = "image", description = "Iris scatter plot")`
3. Verify: widget overlay icons appear on hover, download works

### Phase 6: Standalone Viewer — Hidden Module + Server-Side Logic (follow-up)

**Files**: [R/mcp-wrapper.R](R/mcp-wrapper.R) or new [R/standalone-viewer.R](R/standalone-viewer.R), [R/barebone.R](R/barebone.R), [inst/builtin-templates/bslib-bare/src/index.js](inst/builtin-templates/bslib-bare/src/index.js)

Standalone viewer is a **hidden module** (`standalone_viewer`) generated by `create_barebone_bslib()`. It uses Shiny's server-side session so it has access to reactive domains, output bindings, and the full Shiny lifecycle.

1. **`standalone_viewer(outputId, token, session)`**: Server-side function (exported or internal). Uses `mcp_get_shiny_entry(token)` to look up the originating module session, retrieves render info via `entry$output_renderers$get(outputId)`, gets the render function via `module_session$getOutput(ns(outputId))`, re-assigns under `shiny::withReactiveDomain(module_session, { ... })` into the viewer session's output
2. **Hidden module**: Create `modules/standalone_viewer/` with UI (single full-viewport output container) and server (calls `standalone_viewer()`). Mark as `hidden: yes` in `modules.yaml` so it doesn't appear in sidebar
3. **Wire popout JS**: Update the popout icon click handler to navigate to the standalone viewer module URL: `window.open("?module=standalone_viewer&outputId=" + outputId + "&token=" + token)`
4. **Update `create_barebone_bslib()`** in [R/barebone.R](R/barebone.R): Generate the `standalone_viewer` hidden module directory and files, add entry to `modules.yaml`
5. **Token exposure**: Include `session$token` in the `shidashi.register_output_widgets` custom message so JS has it for the popout URL

### Phase 7: DESCRIPTION + Downstream Compatibility

1. ~~Add `threeBrain` to Suggests in DESCRIPTION~~ (user will add manually)
2. Add NEWS.md entry announcing `register_output()` as a new feature: server-side output registration with download/popout widget support
3. Run `devtools::check()`

## Resolved Questions

1. **Download modal**: Shiny modal (`showModal`). Round-trip is necessary since there could be reactive configurations in the future. Modal fields vary by `download_type` — see Phase 1 for details.

2. **Backward compatibility**: NOT a breaking change. `register_output()` is already used server-side in rave-pipelines. We are clarifying usage: server-only, no fallback needed.

3. **`find_expr` with `::` prefix**: Yes, handle `shiny::renderPlot(...)` by resolving through `getExportedValue()`.

4. **Module name**: `standalone_viewer` (no special prefix) — rave-pipelines already uses this name.

5. **threeBrain in Suggests**: User adds manually. Code uses `asNamespace("threeBrain")` for access.