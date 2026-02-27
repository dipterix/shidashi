# Add or remove 'HTML' class from 'RAVE' application

Only works in template framework provided by 'shidashi' package, see
[`use_template`](https://dipterix.org/shidashi/reference/use_template.md)

## Usage

``` r
add_class(selector, class, session = shiny::getDefaultReactiveDomain())

remove_class(selector, class, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- selector:

  'CSS' selector

- class:

  class to add or to remove from selected elements

- session:

  shiny session

## Value

No value is returned

## Examples

``` r
server <- function(input, output, session){

  # Add class `hidden` to element with ID `elemid`
  add_class("#elemid", "hidden")

  # Remove class `hidden` from element with class `shiny-input-optional`
  remove_class(".shiny-input-optional", "hidden")
}
```
