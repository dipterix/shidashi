# shidashi Migration Plan: AdminLTE3 → bslib (Bootstrap 5)

## Goal

Replace AdminLTE3 dependency with bslib + custom components. Preserve
all 22 public interfaces (16 R functions + 6 JS message handlers) used
by ravedash and rave-pipelines.

## Design Decisions

| Decision            | Choice                                                                                                    | Rationale                                                                     |
|---------------------|-----------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| Dashboard shell     | [`bslib::page_fillable()`](https://rstudio.github.io/bslib/reference/page_fillable.html) + custom sidebar | More flexibility to replicate current layout                                  |
| Iframe management   | Custom lightweight JS                                                                                     | Removes largest AdminLTE dependency                                           |
| JS build system     | esbuild                                                                                                   | Simpler config, faster builds than webpack                                    |
| Bootstrap loading   | `suppressDependencies("bootstrap")` + vendor BS5                                                          | Avoids runtime bslib version coupling                                         |
| Legacy template     | Keep AdminLTE3-bare available                                                                             | Non-breaking for existing deployments                                         |
| Function signatures | Preserve exactly                                                                                          | ravedash/rave-pipelines must work without code changes                        |
| Dark mode class     | Keep `.dark-mode` on `<body>`                                                                             | ravedash uses `add_class`/`remove_class` with CSS selectors that depend on it |

## Interfaces to Preserve (ravedash surface area)

### R Functions (16)

| \#  | Function                                                                                    | Category           |
|-----|---------------------------------------------------------------------------------------------|--------------------|
| 1   | [`render()`](https://dipterix.org/shidashi/reference/render.md)                             | App launcher       |
| 2   | [`adminlte_ui()`](https://dipterix.org/shidashi/reference/adminlte.md)                      | UI generator       |
| 3   | `template_settings$set()`                                                                   | Configuration      |
| 4   | [`show_notification()`](https://dipterix.org/shidashi/reference/notification.md)            | Notifications      |
| 5   | [`clear_notifications()`](https://dipterix.org/shidashi/reference/notification.md)          | Notifications      |
| 6   | [`card()`](https://dipterix.org/shidashi/reference/card.md)                                 | UI components      |
| 7   | [`card_tool()`](https://dipterix.org/shidashi/reference/card_tool.md)                       | UI components      |
| 8   | [`card_tabset()`](https://dipterix.org/shidashi/reference/card_tabset.md)                   | UI components      |
| 9   | [`flex_container()`](https://dipterix.org/shidashi/reference/flex_container.md)             | Layout             |
| 10  | [`flex_item()`](https://dipterix.org/shidashi/reference/flex_container.md)                  | Layout             |
| 11  | [`as_icon()`](https://dipterix.org/shidashi/reference/as_icon.md)                           | Utilities          |
| 12  | [`add_class()`](https://dipterix.org/shidashi/reference/add-remove-html-class.md)           | DOM manipulation   |
| 13  | [`remove_class()`](https://dipterix.org/shidashi/reference/add-remove-html-class.md)        | DOM manipulation   |
| 14  | [`register_session_id()`](https://dipterix.org/shidashi/reference/javascript-tunnel.md)     | Session management |
| 15  | [`register_session_events()`](https://dipterix.org/shidashi/reference/javascript-tunnel.md) | Session management |
| 16  | [`get_theme()`](https://dipterix.org/shidashi/reference/javascript-tunnel.md)               | Theming            |

### JS Message Handlers (6)

| \#  | Handler                       | Purpose               |
|-----|-------------------------------|-----------------------|
| 17  | `shidashi.set_current_module` | Set active module     |
| 18  | `shidashi.shutdown_session`   | Shutdown              |
| 19  | `shidashi.open_iframe_tab`    | Switch module tab     |
| 20  | `shidashi.set_html`           | Set element innerHTML |
| 21  | `shidashi.add_class`          | Add CSS class         |
| 22  | `shidashi.remove_class`       | Remove CSS class      |

------------------------------------------------------------------------

## Phase 1 — New Template: `inst/builtin-templates/bslib-bare/`

### 1.1 Create template scaffold

Create `inst/builtin-templates/bslib-bare/` with this structure:

    bslib-bare/
      index.html              # Main shell (shiny::htmlTemplate)
      modules.yaml            # Copy from AdminLTE3-bare
      views/
        header.html           # BS5 deps + shidashi.js/css
        footer.html           # Register shidashi on shiny:connected
        404.html              # Error page (BS5 classes)
        500.html              # Error page (BS5 classes)
        card.html             # Card component view
        card2.html            # Card2 (direct-chat) view
        card-tabset.html      # Tabset card view
        info-box.html         # Info box view
        accordion-item.html   # Accordion item view
        menu-item.html        # Sidebar nav item view
        menu-item-dropdown.html # Sidebar group view
        preview.html          # Standalone preview wrapper
      www/
        shidashi/
          js/index.js         # Built output (26KB)
          css/shidashi.css    # Built output (28KB)
        bootstrap/
          js/bootstrap.bundle.min.js  # Vendored BS5 (80KB)
      src/                    # esbuild source
        index.js              # Entry point — ShidashiApp class
        iframe-manager.js     # Custom iframe tab manager
        sidebar.js            # Sidebar toggle/search/treeview
        shidashi.scss         # Styles (BS5 variables, no deprecation warnings)
      modules/                # Empty scaffold
      package.json            # esbuild + bootstrap 5 + sass
      esbuild.config.mjs      # Build config

Create directory structure

Copy `modules.yaml` from AdminLTE3-bare

### 1.2 Write `index.html`

Replace AdminLTE3 shell with custom BS5 markup:

Replace `data-widget="pushmenu"` → `data-shidashi-toggle="sidebar"`

Replace `<aside class="main-sidebar sidebar-dark-primary">` →
`<nav class="shidashi-sidebar">`

Replace `<div class="content-wrapper iframe-mode" data-widget="iframe">`
→ `<div class="shidashi-content" data-shidashi-widget="iframe-manager">`

Keep `{{ shidashi::include_view("header.html") }}`,
`{{ shidashi::adminlte_sidebar(...) }}`,
`{{ shidashi::include_view("footer.html") }}` template expressions

Use BS5 utility classes (`ms-auto` not `ml-auto`, `data-bs-toggle` not
`data-toggle`)

Write index.html

### 1.3 Write view templates

`views/header.html` — `suppressDependencies("bootstrap")` + load
vendored BS5 bundle + shidashi.js + shidashi.css

`views/footer.html` — register shidashi on `shiny:connected` (remove
jQuery dependency for init)

`views/404.html` — update to BS5 classes (`float-sm-end` not
`float-sm-right`)

`views/500.html` — update to BS5 classes

`views/card.html` — update `collapsed-card` → `shidashi-collapsed`,
`data-shidashi-card-action`

`views/card2.html` — update direct-chat markup for BS5,
`data-shidashi-action="chat-toggle"`

`views/card-tabset.html` — `data-bs-toggle="tab"`

`views/info-box.html` — no AdminLTE dependency, kept as-is

`views/accordion-item.html` — `data-bs-toggle="collapse"`,
`data-bs-parent`

`views/menu-item.html` — updated nav classes for custom sidebar

`views/menu-item-dropdown.html` — updated for BS5 collapse

`views/preview.html` — updated body class and layout

------------------------------------------------------------------------

## Phase 2 — Rewrite `shidashi.js` with esbuild

### 2.1 Set up build system

Create `package.json` with `esbuild` (^0.27.2), `bootstrap` (^5.3.3),
`sass` (^1.80.0), `esbuild-sass-plugin` (^3.6.0)

Create `esbuild.config.mjs` bundling `src/index.js` →
`www/shidashi/js/index.js` and `src/shidashi.scss` →
`www/shidashi/css/shidashi.css`

### 2.2 Write `src/iframe-manager.js`

Custom replacement for AdminLTE3’s `$.fn.IFrame` plugin:

Manages tab bar (`<ul class="shidashi-tab-bar">`) and iframe container
(`<div class="shidashi-iframe-container">`)

Methods: `openTab(url, title)`, `closeTab(id)`, `closeAllTabs()`,
`closeOtherTabs()`, `activateTab(id)`, `scrollTabBar(direction)`,
`fullscreen()`

Each tab creates a hidden `<iframe>` shown/hidden on activation (not
destroyed) for state preservation

Must support `shidashi.open_iframe_tab` message handler (used by
ravedash `switch_module()`)

Implement iframe-manager.js

### 2.3 Write `src/sidebar.js`

Custom sidebar manager:

Toggle open/close with CSS transition

Highlight active item based on current iframe URL

`data-shidashi-toggle="sidebar"` trigger

Collapsible groups using BS5 `Collapse` API

Search filter (replaces AdminLTE’s `data-widget="sidebar-search"`)

Implement sidebar.js

### 2.4 Rewrite `src/index.js` — the `shidashi` class

Preserve ALL existing Shiny message handlers. Replace AdminLTE3 jQuery
plugin calls:

| AdminLTE3 Plugin                                                  | Replacement                                                   |
|-------------------------------------------------------------------|---------------------------------------------------------------|
| `.CardWidget("collapse"/"expand"/"maximize"/"minimize"/"remove")` | Custom CSS class toggles + BS5 Collapse                       |
| `.DirectChat("toggle")`                                           | Custom CSS class toggle                                       |
| `.Toasts('create', ...)`                                          | BS5 Toast component                                           |
| `.IFrame(...)`                                                    | Delegate to `iframe-manager.js`                               |
| OverlayScrollbars v1 (jQuery)                                     | OverlayScrollbars v2 (vanilla) or CSS `scrollbar-width: thin` |

Preserve: - `Shiny.OutputBinding` for `progressOutputBinding` and
`clipboardOutputBinding` - `localStorage`-based session sync mechanism -
Theme management with `.dark-mode` body class

Implement shidashi class with all message handlers

Implement custom card widget operations

Implement toast notifications via BS5

Implement output bindings (progress, clipboard)

Implement session sync (localStorage broadcast)

Implement theme management (dark/light toggle)

### 2.5 Write `src/shidashi.scss`

Port from AdminLTE3 variables to BS5:

Replace AdminLTE3 color variables (`$blue`, `$gray-dark`) with BS5 CSS
custom properties (`--bs-primary`, etc.)

Replace `sidebar-dark-primary`/`sidebar-light-primary` →
`shidashi-sidebar--dark`/`shidashi-sidebar--light`

Keep `.dark-mode` body class for backward compat

Port iframe-mode dimensions, flip-box, progress bar, back-to-top,
theme-switch styles

Add sidebar + iframe-manager layout styles

Port SCSS to BS5 variables (using `@use` modules, no deprecation
warnings)

Add sidebar layout styles

Add iframe-manager styles

### 2.6 Build and verify

Run `npm install && npm run build` — clean build, zero warnings

Verify `www/shidashi/js/index.js` (26KB) and
`www/shidashi/css/shidashi.css` (28KB) produced

------------------------------------------------------------------------

## Phase 3 — Update R Source Files

### 3.1 `R/ui-adminlte.R` — `adminlte_ui()` and `adminlte_sidebar()`

Keep function signatures identical

[`adminlte_sidebar()`](https://dipterix.org/shidashi/reference/adminlte.md):
update output markup to use BS5-compatible classes and `data-bs-*`
attributes

View templates (menu-item.html, menu-item-dropdown.html) handle the
actual HTML changes

[`adminlte_ui()`](https://dipterix.org/shidashi/reference/adminlte.md)
dispatches to the correct template based on
[`template_root()`](https://dipterix.org/shidashi/reference/template_settings.md)

[`adminlte_sidebar()`](https://dipterix.org/shidashi/reference/adminlte.md)
— template-agnostic, works with both templates

[`adminlte_ui()`](https://dipterix.org/shidashi/reference/adminlte.md) —
template-agnostic, verified with bslib-bare

### 3.2 `R/card.R` — `card()`, `card2()`, operate functions

Keep all function signatures identical

Update generated HTML class references for BS5 compatibility

HTML changes are mostly in view templates (Phase 1.3)

Card-related R code uses BS5 class names (changes in view templates)

### 3.3 `R/card-tabset.R` — `card_tabset()` and operate functions

Keep function signatures identical

Update tab markup: `data-toggle="tab"` → `data-bs-toggle="tab"`
(generated in R, not view template)

`nav-tabs` class name stays the same (works in BS5)

Updated
[`card_tabset()`](https://dipterix.org/shidashi/reference/card_tabset.md):
`data-bs-toggle="tab"`, `ms-auto`

### 3.4 `R/card-tool.R` — `card_tool()`

Keep signature identical

Update `data-card-widget` → `data-shidashi-card-action`

Keep Font Awesome 5 icons

Updated
[`card_tool()`](https://dipterix.org/shidashi/reference/card_tool.md):
`data-shidashi-card-action`

### 3.5 `R/accordion.R` — `accordion()`, `accordion_item()`

Keep function signatures identical

HTML changes handled by accordion-item.html view template (Phase 1.3)

Verify
[`accordion_operate()`](https://dipterix.org/shidashi/reference/accordion.md)
JS message name stays `shidashi.accordion`

Accordion R code compatible — delegates to view templates

### 3.6 `R/info-box.R` — `info_box()`, `flip_box()`

Keep function signatures identical

`info-box` is custom CSS, no AdminLTE dependency

`flip_box` uses custom CSS animations

info-box/flip-box compatible — `data-bs-toggle` updated

### 3.7 `R/notification.R` — `show_notification()`, `clear_notifications()`

Keep function signatures identical

R side sends `shidashi.show_notification` message — keep same message
name

JS side change (AdminLTE Toasts → BS5 Toast) handled in Phase 2

Notification R code compatible — pure message-based

### 3.8 `R/widgets.R` — `flex_container()`, `flex_item()`, `back_top_button()`, `add_class()`, `remove_class()`

`flex_container/flex_item`: inline styles, no AdminLTE dependency — keep
as-is

`add_class/remove_class`: framework-agnostic — keep as-is

[`back_top_button()`](https://dipterix.org/shidashi/reference/back_top_button.md):
update `data-toggle="dropdown"` → `data-bs-toggle="dropdown"`

Updated
[`back_top_button()`](https://dipterix.org/shidashi/reference/back_top_button.md):
`data-bs-toggle`, `visually-hidden`, `dropdown-menu-end`

### 3.9 `R/menu-item.R` — `as_icon()`, `as_badge()`

[`as_icon()`](https://dipterix.org/shidashi/reference/as_icon.md):
generates `<i class="fas fa-...">` — keep as-is (FA works with BS5)

[`as_badge()`](https://dipterix.org/shidashi/reference/as_badge.md):
update `badge badge-danger` → `badge bg-danger` (BS5 badge classes)

[`as_badge()`](https://dipterix.org/shidashi/reference/as_badge.md) —
user-provided class strings, no changes needed (backward compatible)

### 3.10 `R/barebone.R` — `create_barebone()`

Default to copying `bslib-bare` template instead of `AdminLTE3-bare`

Update generated `R/common.R`:

- Remove AdminLTE-specific body classes (`sidebar-mini`, `layout-fixed`,
  `navbar-iframe-hidden`)
- Add bslib-compatible equivalents

Generated `server.R` is template-agnostic — no change needed

Added `create_barebone_bslib()` internal function for new template

`create_barebone()` kept for AdminLTE3 backward compat

Generated `R/common.R` updated for bslib template

### 3.11 `R/render.R` — `render()`

Keep signature identical

Writes `ui.R` containing
[`shidashi::adminlte_ui()`](https://dipterix.org/shidashi/reference/adminlte.md)
— no change needed

[`render()`](https://dipterix.org/shidashi/reference/render.md)
compatible — template-agnostic

### 3.12 `R/settings.R`

Add setting for template type (default `"bslib-bare"`)

[`template_root()`](https://dipterix.org/shidashi/reference/template_settings.md)
prefers `bslib-bare` → `AdminLTE3` → `AdminLTE3-bare`

### 3.13 No changes needed

These files have no AdminLTE dependencies:

- `R/progress.R` — custom Shiny output binding
- `R/clipboard.R` — custom Shiny output binding
- `R/shared-session.R` — localStorage-based sync, framework-agnostic
- `R/aaa.R` — utility functions
- `R/zzz.R` — package hooks
- `R/utils.R` — internal utilities

### 3.14 `DESCRIPTION`

Added `bslib (>= 0.5.0)` to Suggests (not Imports — BS5 is vendored)

Consider replacing `httr` with
[`shiny::parseQueryString()`](https://rdrr.io/pkg/shiny/man/parseQueryString.html)
(httr is only used for URL parsing)

### 3.15 `NAMESPACE`

Run `devtools::document()` to regenerate after all R changes (no new
exports added)

------------------------------------------------------------------------

## Phase 4 — Testing & Compatibility

### 4.1 New template smoke test

`create_barebone(tempdir())` →
[`render()`](https://dipterix.org/shidashi/reference/render.md) —
dashboard loads

Sidebar renders with correct module links

Clicking sidebar item opens module in iframe

Iframe tab bar works (open, close, switch, close-all, close-others)

Dark/light theme toggle works

Theme propagates across iframes via
[`register_session_events()`](https://dipterix.org/shidashi/reference/javascript-tunnel.md)
/
[`get_theme()`](https://dipterix.org/shidashi/reference/javascript-tunnel.md)

[`register_session_id()`](https://dipterix.org/shidashi/reference/javascript-tunnel.md)
cross-iframe input sync works

### 4.2 Widget verification

[`card()`](https://dipterix.org/shidashi/reference/card.md) renders,
collapse/expand/maximize works

[`card2()`](https://dipterix.org/shidashi/reference/card.md) renders,
front/back toggle works

[`card_tabset()`](https://dipterix.org/shidashi/reference/card_tabset.md)
renders, tab insert/remove/activate works

[`accordion()`](https://dipterix.org/shidashi/reference/accordion.md) /
[`accordion_item()`](https://dipterix.org/shidashi/reference/accordion_item.md)
renders, collapse works

[`info_box()`](https://dipterix.org/shidashi/reference/info_box.md)
renders correctly

[`flip_box()`](https://dipterix.org/shidashi/reference/flip_box.md)
renders, flip animation works

[`show_notification()`](https://dipterix.org/shidashi/reference/notification.md)
/
[`clear_notifications()`](https://dipterix.org/shidashi/reference/notification.md)
works (BS5 Toast)

[`progressOutput()`](https://dipterix.org/shidashi/reference/progressOutput.md)
/
[`renderProgress()`](https://dipterix.org/shidashi/reference/progressOutput.md)
works

[`clipboardOutput()`](https://dipterix.org/shidashi/reference/clipboardOutput.md)
/
[`renderClipboard()`](https://dipterix.org/shidashi/reference/clipboardOutput.md)
works

[`flex_container()`](https://dipterix.org/shidashi/reference/flex_container.md)
/
[`flex_item()`](https://dipterix.org/shidashi/reference/flex_container.md)
layout works

### 4.3 Backward compatibility

AdminLTE3-bare template still works when explicitly selected

Existing projects using AdminLTE3-bare continue to function

### 4.4 ravedash integration

Install updated shidashi, run ravedash

Verify all 16 R function interfaces work

Verify all 6 JS message handlers work

`switch_module()` (uses `shidashi.open_iframe_tab`) works

`set_card_badge()` (uses `shidashi.set_html`, `shidashi.add_class`,
`shidashi.remove_class`) works

### 4.5 Package checks

`devtools::check()` — no new NOTEs/WARNINGs/ERRORs

Visual comparison of key widgets between old and new templates

------------------------------------------------------------------------

## Phase 5 — rave-pipelines Compatibility & Polish

These items ensure bslib-bare matches the features used by
rave-pipelines.

### 5.1 Module groups & ordering in `modules.yaml`

The R infrastructure
([`module_info()`](https://dipterix.org/shidashi/reference/module_info.md),
[`adminlte_sidebar()`](https://dipterix.org/shidashi/reference/adminlte.md),
`menu_item_dropdown()`) already supports: - `groups:` section with
`icon`, `badge`, `order`, `open` per group - `divider:` section with
`order` per divider (renders as `nav-header nav-divider`) - Module-level
`group:` assignments

The bslib-bare `modules.yaml` only uses a flat list. Add demo
groups/dividers to showcase the feature.

**Bug fix**: `sidebar.js` queries `.shidashi-sidebar-nav` but the
template has `.shidashi-nav` inside `.shidashi-sidebar-content`. Fix the
selector to match the actual DOM.

Fix `sidebar.js` `_navContainer` selector: `.shidashi-sidebar-nav` →
`.shidashi-sidebar-content`

Add `groups:` and `divider:` sections to `modules.yaml`

### 5.2 Sidebar dark theme under light mode

rave-pipelines defaults to a dark sidebar even under light body mode.
The current implementation conditionally applies
`shidashi-sidebar--dark`/`--light` in `index.html`, and JS toggles
`sidebar-dark`/`sidebar-light`.

Ensure the sidebar stays dark-themed when the body is in light mode
(default rave-pipelines behavior), while still respecting explicit user
overrides.

SCSS: Ensure dark sidebar styles are the default, `sidebar-light` is
opt-in

JS: Only toggle sidebar theme classes when explicitly requested

### 5.3 Navbar items for rave-action testing

rave-pipelines module-ui.html files include navbar items like:

``` html
<a href="#" class="nav-link rave-button" rave-action='{"type": "toggle_loader"}'>
  <i class="fas fa-database"></i> Load data
</a>
```

These are specific to module iframes and handled by ravedash, not
shidashi. No changes needed in the main template — ravedash adds these
in its own module-ui.html templates.

No action needed — rave-button navbar items are module-level, not
template-level

### 5.4 Navbar message broadcasting to sub-windows (rave-action)

rave-pipelines’ `class-shidashi.js` handles `.rave-button` clicks inside
module iframes by parsing `rave-action` JSON and calling
`Shiny.setInputValue("@rave_action@", ...)`. This is implemented in
ravedash, not shidashi.

shidashi’s role is to support `broadcastEvent()` and cross-iframe
communication. The current `broadcastEvent()` in `index.js` already
fires a `CustomEvent` and sends to Shiny. Add `notifyIframes()` to
broadcast events to all managed iframes.

Add `notifyIframes(type, message)` method to IFrameManager

Wire up `broadcastEvent()` to also notify iframes

### 5.5 Super thin scrollbar support

AdminLTE3 uses webkit scrollbar pseudo-elements for 0.5rem thin
scrollbars on hover. The current SCSS already has
`scrollbar-width: thin`. Add webkit `::-webkit-scrollbar` styles and
show-on-hover behavior for the sidebar.

Add webkit scrollbar styles (`::-webkit-scrollbar`,
`::-webkit-scrollbar-thumb`)

Sidebar: hide scrollbar by default, show thin on hover

### 5.6 Brand icon location fix

Ensure `shidashi-brand-link` vertical centering and spacing matches
AdminLTE3’s `.brand-link` padding. Current implementation uses
`height: $navbar-height` + `padding: 0 1rem` which may not vertically
center the logo/text.

Fix brand link padding and vertical centering
