# A shiny color picker

Displays color right by the color names for better user experience;
implemented using vanilla shiny selector

## Usage

``` r
colormapSelectInput(
  inputId,
  label,
  colormaps,
  selected = NULL,
  continuous = FALSE
)
```

## Arguments

- inputId, label, selected:

  passed to shiny
  [`selectInput`](https://rdrr.io/pkg/shiny/man/selectInput.html);
  `selected` must be one of the names of color map list

- colormaps:

  A named list with name being the color-map names and values being a
  character vector of key colors

- continuous:

  whether the color map is continuous; default is false

## Value

A shiny selector

## Examples

``` r



colormaps <- list(
  Dark2 = c("#1b9e77", "#d95f02", "#7570b3", "#e7298a",
            "#66a61e", "#e6ab02", "#a6761d", "#666666"),
  Paired = c("#a6cee3", "#1f78b4", "#b2df8a", "#33a02c",
             "#fb9a99", "#e31a1c", "#fdbf6f", "#ff7f00"),
  Pastel1 = c("#fbb4ae", "#b3cde3", "#ccebc5", "#decbe4",
              "#fed9a6", "#ffffcc", "#e5d8bd", "#fddaec"),
  Set1 = c("#e41a1c", "#377eb8", "#4daf4a", "#984ea3",
           "#ff7f00", "#ffff33", "#a65628", "#f781bf")
)

color_picker <- colormapSelectInput(
  inputId = "colormap", label = "Pick a colormap",
  colormaps = colormaps, continuous = FALSE
)

if (interactive()) {
  shiny::shinyApp(
    ui = color_picker,
    server = function(input, output, server) {
      shiny::observe({
        print(colormaps[[input$colormap]])
      })
    }
  )
}

```
