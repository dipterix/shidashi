# Shiny render plot function with automated theme switcher

A wrapper around
[`renderPlot`](https://rdrr.io/pkg/shiny/man/renderPlot.html), but with
themes automatically set via
[`par`](https://rdrr.io/r/graphics/par.html); only supports base plots.
For ggplot2, please manually call
[`get_theme`](https://dipterix.org/shidashi/reference/fire_event.md) to
get the theme.

## Usage

``` r
renderPlot2(expr, ..., env = parent.frame(), quoted = FALSE)
```

## Arguments

- expr, env, quoted, ...:

  passed to
  [`renderPlot`](https://rdrr.io/pkg/shiny/man/renderPlot.html)

## Value

See [`renderPlot`](https://rdrr.io/pkg/shiny/man/renderPlot.html)

## Examples

``` r

server <- function(input, output, session) {

  output$plot <- renderPlot2({
    plot(rnorm(100))
  })

}
```
