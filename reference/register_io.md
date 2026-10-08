# Register Shiny Inputs and Outputs for `MCP` Access

Register `shiny` inputs and outputs for `MCP` (Model Context Protocol)
agent access.

`register_input()` wraps a `shiny` input constructor to register
metadata. It evaluates `expr` and returns the UI element, with `tooltip`
as its hover tip (the `HTML` `title` attribute). `as_tooltip()` gives
the default hover tip: the first sentence of `description`.

`register_output()` is a server-side function that registers a render
function call (e.g. `renderPlot({...})`), assigns it to
`session$output`, registers the `MCP` output spec, and sets up
download-widget handlers. The UI overlay icons are injected entirely by
`JS`.

## Usage

``` r
register_input(
  expr,
  inputId,
  update,
  description = "",
  tooltip = as_tooltip(description),
  writable = TRUE,
  hint = "no_hint",
  quoted = FALSE,
  env = parent.frame()
)

input_hint_classes

as_tooltip(description)

register_output(
  expr,
  outputId,
  description = "",
  quoted = FALSE,
  env = parent.frame(),
  ...,
  output_opts = list(),
  download_function = NULL,
  download_type = c("image", "htmlwidget", "threeBrain", "no-download", "data",
    "stream_viz"),
  extension = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- expr:

  For `register_input`: a call expression that creates a `shiny` input
  widget. For `register_output`: a render function call such as
  `renderPlot({...})`.

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

- tooltip:

  character string shown when the mouse hovers over the input; defaults
  to the first sentence of `description` (see `as_tooltip()`). Set to
  `NULL` for no hover tip. The hover tip is added only when the outer
  tag of the UI element is an input (a `button`, `a`, `input`, `select`,
  or `textarea` tag, or a tag with class `shiny-input-container`)
  without a `title`; other elements, such as cards, are returned
  unchanged.

- writable:

  logical (default `TRUE`). Whether the `MCP` update tool is allowed to
  change this input.

- hint:

  character string, one of `input_hint_classes`: what an agent does with
  the input before acting, reported by the `shiny_input_info` tool. The
  `loader_*` hints apply before loading data and the `analysis_*` hints
  before running the module's main action: `*_mandatory` inputs are
  asked from the user, `*_optional` inputs may keep their current or
  default value, and `*_forbidden` inputs are left alone. The default
  `"no_hint"` gives no guidance.

- quoted:

  logical (default `FALSE`). If `TRUE`, `expr` is treated as already
  quoted; otherwise it is captured with
  [`substitute()`](https://rdrr.io/r/base/substitute.html).

- env:

  the environment in which to evaluate `expr`.

- outputId:

  character string. The `shiny` output ID (without the module namespace
  prefix).

- ...:

  reserved for future use.

- output_opts:

  a named list of extra options for the output (e.g. width, height
  defaults).

- download_function:

  a custom download handler function. When `download_type = "data"`,
  this function receives the file path and writes the download content.

- download_type:

  character string. One of `"image"`, `"threeBrain"`, `"data"`, or
  `"no-download"`.

- extension:

  character vector of allowed file extension for download, or `NULL`.

- session:

  the `shiny` session object. For `register_output`, defaults to
  [`shiny::getDefaultReactiveDomain()`](https://rdrr.io/pkg/shiny/man/domains.html).

## Value

`register_input` returns the evaluated UI element, with `tooltip` as the
`title` of an input (see `tooltip`). `as_tooltip` returns the first
sentence of `description` as a character string (`""` when it is blank).
`register_output` is called for its side effects (assigning the render
function and registering widgets) and returns `NULL` invisibly.

## See also

[`init_app`](https://dipterix.org/shidashi/reference/init_app.md),
[`mcp_wrapper`](https://dipterix.org/shidashi/reference/mcp_wrapper.md)

## Examples

``` r
# The default hover tip: the first sentence of the description
as_tooltip("Plot threshold, e.g. 0.5. Agents set it before running.")
#> [1] "Plot threshold, e.g. 0.5."

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

# inside a shidashi module server function:
register_output(
  expr = renderPlot({ plot(iris) }),
  outputId = "my_plot",
  description = "Scatter plot of iris data",
  download_type = "image"
)
} # }
```
