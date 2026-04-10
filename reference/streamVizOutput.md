# Output placeholder for a streaming visualization widget

Use in a Shiny UI to reserve a slot for a multi-channel signal viewer
that is driven by binary stream data.

## Usage

``` r
streamVizOutput(outputId, width = "100%", height = "400px")
```

## Arguments

- outputId:

  Character scalar. Output ID that matches the corresponding
  [`renderStreamViz`](https://dipterix.org/shidashi/reference/renderStreamViz.md)
  call.

- width, height:

  CSS width and height of the widget container.

## Value

An HTML output element suitable for inclusion in a Shiny UI.

## See also

[`renderStreamViz`](https://dipterix.org/shidashi/reference/renderStreamViz.md),
[`updateStreamViz`](https://dipterix.org/shidashi/reference/updateStreamViz.md)
