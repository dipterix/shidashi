# Open, close, or toggle the drawer panel

Send messages to the client to open, close, or toggle the off-canvas
drawer panel on the right side of the dashboard.

## Usage

``` r
drawer_open(session = shiny::getDefaultReactiveDomain())

drawer_close(session = shiny::getDefaultReactiveDomain())

drawer_toggle(session = shiny::getDefaultReactiveDomain())
```

## Arguments

- session:

  shiny session

## Value

No value is returned (called for side effect).

## Examples

``` r
server <- function(input, output, session){
  # Open the drawer
  drawer_open()

  # Close the drawer
  drawer_close()

  # Toggle the drawer
  drawer_toggle()
}
```
