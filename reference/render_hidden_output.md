# Render an Output Even When It Is Hidden

By default `shiny` does not render outputs that are hidden, for example
inside an inactive tab or a collapsed card (`suspendWhenHidden = TRUE`).
`render_hidden_output()` turns this off for one output, so the output
renders at the next flush even when hidden. With `once = TRUE`, the
option is restored after that flush.

## Usage

``` r
render_hidden_output(
  outputId,
  session = shiny::getDefaultReactiveDomain(),
  once = TRUE
)
```

## Arguments

- outputId:

  character string. The `shiny` output ID (without the module namespace
  prefix).

- session:

  the `shiny` session object.

- once:

  logical (default `TRUE`). Whether to restore the option after the next
  flush; when `FALSE`, the output keeps rendering while hidden until the
  returned function is called.

## Value

A function (invisible) that restores the option; calling it more than
once has no further effect. Nothing is changed when the output already
renders while hidden.

## Examples

``` r
if (FALSE) { # \dontrun{
# inside a shidashi module server function:
register_output(renderPlot({ plot(1:10) }), outputId = "my_plot")

# render `my_plot` once, even while its tab is not shown
render_hidden_output("my_plot")
} # }
```
