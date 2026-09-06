# A re-orderable list of objects as a shiny input

Displays the selected objects as a vertical list; entries can be dragged
to re-order and removed with the `X` button on the right. The value is a
character vector of the entry keys, in the order shown on screen.
Implemented using vanilla shiny
[`selectizeInput`](https://rdrr.io/pkg/shiny/man/selectInput.html),
hence no additional 'JavaScript' library is needed.

## Usage

``` r
objectListInput(
  inputId,
  label = NULL,
  choices = NULL,
  selected = NULL,
  width = NULL,
  placeholder = "(No object selected)",
  sortable = TRUE,
  removable = TRUE,
  allow_readd = TRUE
)

updateObjectListInput(
  session = shiny::getDefaultReactiveDomain(),
  inputId,
  label = NULL,
  choices = NULL,
  selected = choices
)
```

## Arguments

- inputId, label, width:

  passed to
  [`selectizeInput`](https://rdrr.io/pkg/shiny/man/selectInput.html)

- choices:

  a named list or character vector of the entries; the names are the
  text displayed in each row and the values are the entry keys returned
  by the input; the order of `choices` is the order of the rows

- selected:

  keys of the entries to show; default is all of `choices`

- placeholder:

  text to display when the list is empty

- sortable:

  whether the entries can be dragged to re-order; requires 'jQuery' 'UI'
  shipped with shiny, and is silently disabled when unavailable

- removable:

  whether each entry has a button to remove itself

- allow_readd:

  whether the entries can be selected again from a drop-down menu; when
  `FALSE` the list only shows what the server puts in it, and removing
  an entry is final until it is added again from the server; when `TRUE`
  a removed entry stays available in the menu and re-selecting it
  appends it to the end of the list; default is `TRUE`

- session:

  shiny session

## Value

`objectListInput` returns a shiny input; the input value is a character
vector of the entry keys in display order. `updateObjectListInput` is
called for its side effect.

## Examples

``` r


ui <- shiny::basicPage(
  objectListInput(
    inputId = "objects", label = "Selected objects",
    choices = character(),
    selected = character()
  ),
  shiny::actionButton("btn", "Add")
)

if (interactive()) {
  shiny::shinyApp(
    ui = shiny::fluidPage(ui, shiny::verbatimTextOutput("selected")),
    server = function(input, output, session) {
      output$selected <- shiny::renderPrint({ input$objects })

      shiny::bindEvent(
        shiny::observe({
          shidashi::updateObjectListInput(
            inputId = "objects",
            choices = c(
              "Electrode 1 [LA1]" = "elec_1",
              "Streamlines [n=12]" = "streamlines_1",
              "Overlay aparc [discrete]" = "volume_1"
            )
          )
        }),
        input$btn
      )
    }
  )
}

```
