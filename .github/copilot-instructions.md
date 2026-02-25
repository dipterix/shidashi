# Copilot Instructions for shidashi

## Project Overview

`shidashi` is an R package providing Shiny dashboard templates. It is migrating from AdminLTE3 (Bootstrap 4) to bslib (Bootstrap 5). The main template under active development is `bslib-bare` at:

```
inst/builtin-templates/bslib-bare/
```

## Building the bslib-bare Template

The template uses **esbuild** with esbuild-sass-plugin to bundle JS and compile SCSS.

### Build command

```bash
cd inst/builtin-templates/bslib-bare && npm run build
```

This single command compiles both:
- `src/index.js` → `www/shidashi/js/index.js` (IIFE bundle)
- `src/shidashi.scss` → `www/shidashi/css/shidashi.css`

Source maps are generated alongside each output.

### Watch mode (for development)

```bash
cd inst/builtin-templates/bslib-bare && npm run watch
```

### Install dependencies (first time only)

```bash
cd inst/builtin-templates/bslib-bare && npm install
```

**Always run `npm run build` after any changes to files under `src/`.** Do NOT use manual `node -e` or `npx esbuild` one-liners.

## Key Architecture

- **Bootstrap 5** is provided by `bslib` at runtime (NOT vendored). The R function `shidashi::bslib_dependency()` returns bslib theme dependencies.
- **R source files** are in `R/`. Key files: `aaa.R` (bootstrap dep), `barebone.R` (template scaffolding), `settings.R` (template selection), `modules.R` (iframe module loading).
- **Template views** are in `inst/builtin-templates/bslib-bare/views/` — HTML fragments rendered via `httpuv`/`whisker`.
- **JS architecture**: Vanilla JS with `ShidashiApp` class (IIFE, global `Shidashi`). Sub-modules: `iframe-manager.js`, `sidebar.js`.
- **SCSS**: Uses `@use` modules (`sass:meta`, `sass:map`, `sass:string`, `sass:color`). No `@import`.

## Downstream Dependents

Several packages depend on shidashi (notably `ravedash` and `rave-pipelines`). The following 22 interfaces must be preserved:

### R Functions (16)
`render()`, `adminlte_ui()`, `template_settings$set()`, `show_notification()`, `clear_notifications()`, `card()`, `card_tool()`, `card_tabset()`, `flex_container()`, `flex_item()`, `as_icon()`, `add_class()`, `remove_class()`, `register_session_id()`, `register_session_events()`, `get_theme()`

### JS Message Handlers (6)
`shidashi.set_current_module`, `shidashi.shutdown_session`, `shidashi.open_iframe_tab`, `shidashi.set_html`, `shidashi.add_class`, `shidashi.remove_class`

## Testing

```r
devtools::load_all()
tmp <- file.path(tempdir(), "test-bslib")
unlink(tmp, recursive = TRUE)
create_barebone_bslib(tmp)
render(root_path = tmp)
```

## CSS Class Conventions

- Bootstrap 5 utilities (e.g. `ms-auto`, `visually-hidden`, `float-end`, `dropdown-menu-end`)
- Custom prefix: `shidashi-` for all custom components (sidebar, header, tab-bar, iframe-container, brand-link, etc.)
- Data attributes: `data-shidashi-*` for custom actions, `data-bs-*` for Bootstrap 5
