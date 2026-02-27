# The 'JavaScript' tunnel

The 'JavaScript' tunnel

## Usage

``` r
register_session_id(
  session = shiny::getDefaultReactiveDomain(),
  shared_id = NULL,
  shared_inputs = NA
)

register_session_events(session = shiny::getDefaultReactiveDomain())

get_theme(event_data, session = shiny::getDefaultReactiveDomain())

get_jsevent(
  event_data,
  type,
  default = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- session:

  shiny reactive domain

- shared_id:

  the shared id of the session, usually automatically set

- shared_inputs:

  the input names to share to/from other sessions

- event_data:

  a reactive value list returned by `register_session_events`

- type:

  event type; see 'Details'

- default:

  default value if `type` is missing

## Value

`register_session_id` returns a list of function to control "sharing"
inputs with other shiny sessions with the same `shared_id`.
`register_session_events` returns a reactive value list that reflects
the session state. `get_jsevent` returns events fired by
`shidashi.broadcastEvent` in 'JavaScript'. `get_theme` returns a list of
theme, foreground, and background color.

## Details

The `register_session_id` should be used in the module server function.
It registers a `shared_id` and a `private_id` to the session. The
sessions with the same `shared_id` can synchronize their inputs,
specified by `shared_inputs` even on different browser tabs.

`register_session_events` will read the session events from 'JavaScript'
and passively update these information. Any the event fired by
`shidashi.broadcastEvent` in 'JavaScript' will be available as reactive
value. `get_jsevent` provides a convenient way to read these events
provided the right event types. `get_theme` is a special `get_jsevent`
that with event type `"theme.changed"`.

Function `register_session_id` and `register_session_events` should be
called at the beginning of server functions. They can be called multiple
times safely. Function `get_jsevent` and `get_theme` should be called in
reactive contexts (such as
[`observe`](https://rdrr.io/pkg/shiny/man/observe.html),
[`observeEvent`](https://rdrr.io/pkg/shiny/man/observeEvent.html)).

## Examples

``` r
# shiny server function

library(shiny)
server <- function(input, output, session){
  sync_tools <- register_session_id(session = session)
  event_data <- register_session_events(session = session)

  # if you want to enable syncing. They are suspended by default
  sync_tools$enable_broadcast()
  sync_tools$enable_sync()

  # get_theme should be called within reactive context
  output$plot <- renderPlot({
    theme <- get_theme(event_data)
    mar(bg = theme$background, fg = theme$foreground)
    plot(1:10)
  })

}
```
