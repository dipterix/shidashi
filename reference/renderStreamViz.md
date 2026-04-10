# Render a streaming widget

Server-side render function for
[`streamVizOutput`](https://dipterix.org/shidashi/reference/streamVizOutput.md).
The expression should evaluate to a
[`stream_viz`](https://dipterix.org/shidashi/reference/stream_viz.md)
object.

## Usage

``` r
renderStreamViz(expr, env = parent.frame(), quoted = FALSE)
```

## Arguments

- expr:

  An R expression that returns a
  [`stream_viz`](https://dipterix.org/shidashi/reference/stream_viz.md)
  widget.

- env:

  Environment in which to evaluate `expr`.

- quoted:

  Logical. Whether `expr` is already quoted.

## Value

A server-side render function for use with Shiny.

## See also

[`streamVizOutput`](https://dipterix.org/shidashi/reference/streamVizOutput.md),
[`updateStreamViz`](https://dipterix.org/shidashi/reference/updateStreamViz.md)
