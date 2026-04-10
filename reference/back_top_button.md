# 'HTML' code to generate small back-to-top button

This function is a template function that should be called in 'HTML'
templates before closing the `"</body>"` tag.

When `open_drawer = TRUE`, an additional button is rendered that fires a
`"button.click"` shidashi-event with `type = "open_drawer"`. Module
server code (or
[`chatbot_server`](https://dipterix.org/shidashi/reference/chatbot_server.md))
can observe this event via
[`get_event`](https://dipterix.org/shidashi/reference/fire_event.md) and
call [`drawer_open`](https://dipterix.org/shidashi/reference/drawer.md)
/ [`shiny::renderUI`](https://rdrr.io/pkg/shiny/man/renderUI.html) to
fill the drawer with content.

## Usage

``` r
back_top_button(
  icon = "chevron-up",
  title = "Jump to",
  open_drawer = TRUE,
  drawer_icon = "ellipsis"
)
```

## Arguments

- icon:

  the icon for back-to-top button

- title:

  the expanded menu title

- open_drawer:

  logical; whether to include a drawer-toggle button. Defaults to `TRUE`
  if a `.shidashi-drawer` element will be present in the page (e.g.\\
  from
  [`module_drawer()`](https://dipterix.org/shidashi/reference/module_drawer.md)).

- drawer_icon:

  the icon for the drawer-toggle button; defaults to `"ellipsis"` (three
  dots). Use e.g. `"robot"` for AI-agent modules.

## Value

'HTML' tags

## Examples

``` r
back_top_button()
#> <div class="shidashi-back-to-top">
#>   <a type="button" class="btn btn-default btn-drawer-toggle" href="#" data-shidashi-action="drawer-toggle" title="Open panel">
#>     <i class="fas fa-ellipsis" role="presentation" aria-label="ellipsis icon"></i>
#>   </a>
#>   <div class="btn-group dropup" role="group">
#>     <a type="button" class="btn btn-default btn-go-top border-right-1" href="#">
#>       <i class="fas fa-chevron-up" role="presentation" aria-label="chevron-up icon"></i>
#>     </a>
#>     <button type="button" class="btn btn-default dropdown-toggle dropdown-toggle-split border-left-1" data-toggle="dropdown" data-bs-toggle="dropdown" aria-haspopup="false" aria-expanded="false">
#>       <span class="sr-only visually-hidden">Dropdown-Open</span>
#>     </button>
#>     <div class="dropdown-menu dropdown-menu-end">
#>       <h6 class="dropdown-header">Jump to</h6>
#>     </div>
#>   </div>
#> </div>
back_top_button("rocket")
#> <div class="shidashi-back-to-top">
#>   <a type="button" class="btn btn-default btn-drawer-toggle" href="#" data-shidashi-action="drawer-toggle" title="Open panel">
#>     <i class="fas fa-ellipsis" role="presentation" aria-label="ellipsis icon"></i>
#>   </a>
#>   <div class="btn-group dropup" role="group">
#>     <a type="button" class="btn btn-default btn-go-top border-right-1" href="#">
#>       <i class="fas fa-rocket" role="presentation" aria-label="rocket icon"></i>
#>     </a>
#>     <button type="button" class="btn btn-default dropdown-toggle dropdown-toggle-split border-left-1" data-toggle="dropdown" data-bs-toggle="dropdown" aria-haspopup="false" aria-expanded="false">
#>       <span class="sr-only visually-hidden">Dropdown-Open</span>
#>     </button>
#>     <div class="dropdown-menu dropdown-menu-end">
#>       <h6 class="dropdown-header">Jump to</h6>
#>     </div>
#>   </div>
#> </div>
back_top_button("rocket", drawer_icon = "robot")
#> <div class="shidashi-back-to-top">
#>   <a type="button" class="btn btn-default btn-drawer-toggle" href="#" data-shidashi-action="drawer-toggle" title="Open panel">
#>     <i class="fas fa-robot" role="presentation" aria-label="robot icon"></i>
#>   </a>
#>   <div class="btn-group dropup" role="group">
#>     <a type="button" class="btn btn-default btn-go-top border-right-1" href="#">
#>       <i class="fas fa-rocket" role="presentation" aria-label="rocket icon"></i>
#>     </a>
#>     <button type="button" class="btn btn-default dropdown-toggle dropdown-toggle-split border-left-1" data-toggle="dropdown" data-bs-toggle="dropdown" aria-haspopup="false" aria-expanded="false">
#>       <span class="sr-only visually-hidden">Dropdown-Open</span>
#>     </button>
#>     <div class="dropdown-menu dropdown-menu-end">
#>       <h6 class="dropdown-header">Jump to</h6>
#>     </div>
#>   </div>
#> </div>
```
