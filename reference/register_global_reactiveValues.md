# Register global reactive list

Creates or get reactive value list that is shared within the same shiny
session

## Usage

``` r
register_global_reactiveValues(
  name,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- name:

  character, the key of the list

- session:

  shiny session

## Value

A shiny
[`reactiveValues`](https://rdrr.io/pkg/shiny/man/reactiveValues.html)
object
