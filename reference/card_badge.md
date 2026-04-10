# Create a badge widget located at card header

Create a badge widget located at card header

## Usage

``` r
card_badge(text = NULL, class = NULL, ...)

card_recalculate_badge(
  text = "Recalculate needed",
  class = NULL,
  event_name = "run_analysis",
  ...
)

enable_recalculate_badge(text = "Recalculate needed", ...)

disable_recalculate_badge(text = "Up-to-date", ...)

set_card_badge(
  id = NULL,
  class = NULL,
  text = NULL,
  add_class = NULL,
  remove_class = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- text:

  inner text content of the badge

- class:

  additional 'HTML' class of the badge; for `set_card_badge`, this is
  the class selector of the badge that is to be changed

- ...:

  additional 'HTML' tag attributes

- event_name:

  name of the event to trigger

- id:

  the badge 'HTML' ID to be changed, will be enclosed with session
  namespace `session$ns(id)` automatically.

- add_class, remove_class:

  add or remove class

- session:

  shiny session

## Examples

``` r
library(shidashi)

# UI: a Bootstrap badge with green background
card_badge("Ready", class = "bg-green shidashi-output-status")
#> <span class="right badge shidashi-card-badge bg-green shidashi-output-status">Ready</span>

# server
server <- function(input, output, session) {

  shiny::observe({

    # ... check if the inputs have changed

    set_card_badge(
      class = "shidashi-output-status",
      text = "Refresh needed",
      add_class = "bg-warning",
      remove_class = "bg-success disabled"
    )

  })

}
```
