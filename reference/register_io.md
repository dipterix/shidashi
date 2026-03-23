# Register Shiny Inputs and Outputs for `MCP` Access

Wrap `shiny` input and output constructors to register metadata so that
`MCP` (Model Context Protocol) agent tools can discover, read, and
update them at runtime. When called inside a module loaded by
`shidashi`, the input/output specification is recorded as a side effect
and the UI element is returned. When called outside that context (e.g.
in a plain Shiny app), the functions fall back to simply evaluating
`expr`.

## Usage

``` r
register_input(
  expr,
  inputId,
  update,
  description = "",
  writable = TRUE,
  quoted = FALSE,
  env = parent.frame()
)

register_output(
  expr,
  outputId,
  description = "",
  quoted = FALSE,
  env = parent.frame()
)
```

## Arguments

- expr:

  a call expression that creates a `shiny` input or output widget, e.g.
  `shiny::textInput(inputId = ns("x"), label = "X")` or
  `shiny::plotOutput(ns("plot1"), height = "100%")`.

- inputId:

  character string. The `shiny` input ID (without the module namespace
  prefix).

- update:

  character string. The fully qualified update function, e.g.
  `"shiny::updateTextInput"`. Field mappings such as
  `"shiny::updateSelectInput(value=selected)"` override the default
  argument names passed to the update function.

- description:

  character string. A human-readable description of the input or output
  purpose, exposed to `LLM` agents via `MCP` tools.

- writable:

  logical (default `TRUE`). Whether the `MCP` update tool is allowed to
  change this input.

- quoted:

  logical (default `FALSE`). If `TRUE`, `expr` is treated as already
  quoted; otherwise it is captured with
  [`substitute()`](https://rdrr.io/r/base/substitute.html).

- env:

  the environment in which to evaluate `expr`.

- outputId:

  character string. The `shiny` output ID (without the module namespace
  prefix).

## Value

The evaluated UI element produced by `expr`. The input or output
specification is registered as a side effect.

## See also

[`init_app`](https://dipterix.org/shidashi/reference/init_app.md),
[`mcp_wrapper`](https://dipterix.org/shidashi/reference/mcp_wrapper.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# inside a shidashi module UI function:
ns <- shiny::NS("demo")

register_input(
  expr = shiny::sliderInput(
    inputId = ns("threshold"),
    label = "Threshold",
    min = 0, max = 1, value = 0.5
  ),
  inputId = "threshold",
  update = "shiny::updateSliderInput",
  description = "Filter threshold for the plot"
)

register_output(
  expr = shiny::plotOutput(ns("my_plot"), height = "100%"),
  outputId = "my_plot",
  description = "Scatter plot of filtered data"
)
} # }
```
