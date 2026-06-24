# Drawer shell for module templates

Emits a minimal `.shidashi-drawer` container with a
[`uiOutput`](https://rdrr.io/pkg/shiny/man/htmlOutput.html) placeholder
inside, plus the drawer overlay. The drawer starts empty; module server
code fills it dynamically via
[`shiny::renderUI`](https://rdrr.io/pkg/shiny/man/renderUI.html).

Typical usage in a `module-ui.html` template:


      {{ shidashi::module_drawer() }}

Then in the module server:


      output$shidashi_drawer <- shiny::renderUI({
        shiny::tagList(
          shiny::h5("My settings"),
          shiny::p("Custom drawer content here.")
        )
      })

The `ns()` function from the module's template evaluation environment is
used automatically so that the output ID is properly scoped to the
module namespace.

## Usage

``` r
module_drawer(output_id = "shidashi_drawer")
```

## Arguments

- output_id:

  character; the output ID for the `uiOutput` placeholder inside the
  drawer. Defaults to `"shidashi_drawer"`.

## Value

A
[`shiny::tagList`](https://rstudio.github.io/htmltools/reference/tagList.html)
containing the drawer div and its overlay.
