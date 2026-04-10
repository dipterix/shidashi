# Fire or read a session event

`fire_event` sets a reactive event value on the current session. When
`global = TRUE`, the event is propagated to all sessions that share the
same `shared_id` (i.e. other browser tabs for the same user).

`get_event` reads the current value of an event key from the session
registry.

`get_theme` is a convenience wrapper around `get_event("theme.changed")`
that returns the current dashboard theme.

All three functions must be called inside a Shiny server context.

## Usage

``` r
fire_event(
  key,
  value,
  session = shiny::getDefaultReactiveDomain(),
  global = FALSE
)

get_event(key, session = shiny::getDefaultReactiveDomain(), default = NULL)

get_theme(session = shiny::getDefaultReactiveDomain())
```

## Arguments

- key:

  a single character string identifying the event type

- value:

  the event payload (any R object)

- session:

  a Shiny session (defaults to the current reactive domain)

- global:

  logical; if `TRUE`, the event is broadcast to all sessions sharing the
  same `shared_id`

- default:

  value to return when the event has not been fired yet (used by
  `get_event` only)

## Value

`fire_event` returns `NULL` invisibly. `get_event` returns the last
value fired for `key`, or `default` if none. `get_theme` returns a named
list with three character elements:

- theme:

  Either `"light"` or `"dark"`.

- foreground:

  Hex color string for text / foreground elements.

- background:

  Hex color string for the page background.

Before the browser fires its first theme event, the light-theme fallback
`list(theme = "light", background = "#FFFFFF", foreground = "#000000")`
is returned.

## Details

`get_theme` and `get_event` auto-register the session if needed and must
be called inside a reactive context
([`observe`](https://rdrr.io/pkg/shiny/man/observe.html),
[`observeEvent`](https://rdrr.io/pkg/shiny/man/observeEvent.html),
[`reactive`](https://rdrr.io/pkg/shiny/man/reactive.html), render
functions).

## Examples

``` r

library(shiny)
server <- function(input, output, session) {
  # fire an event
  shidashi::fire_event("my_event", list(a = 1), session = session)

  # read it back
  observe({
    evt <- shidashi::get_event("my_event", session = session)
    print(evt)
  })

  # get_theme must be called within a reactive context
  output$plot <- renderPlot({
    theme <- shidashi::get_theme()
    par(bg = theme$background, fg = theme$foreground)
    plot(1:10)
  })
}

```
