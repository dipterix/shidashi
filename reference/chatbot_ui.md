# Chat-bot UI panel

Returns the UI elements for the AI chat panel: a header bar with a “New
conversation” button and the shinychat widget.

When shinychat is not installed or the chat-bot is disabled via
`options(shidashi.chatbot = FALSE)`, returns an empty
[`tagList()`](https://rstudio.github.io/htmltools/reference/tagList.html).

Typically called inside
[`shiny::renderUI`](https://rdrr.io/pkg/shiny/man/renderUI.html) by
[`chatbot_server()`](https://dipterix.org/shidashi/reference/chatbot_server.md)
to fill a
[`module_drawer`](https://dipterix.org/shidashi/reference/module_drawer.md).
Can also be placed anywhere in module UI directly.

## Usage

``` r
chatbot_ui(id, modes = NULL, default_mode = NULL)
```

## Arguments

- id:

  character; the Shiny input/output namespace for the chat widget.
  Default `"shidashi-chatbot"`.

## Value

A
[`shiny::tagList`](https://rstudio.github.io/htmltools/reference/tagList.html)
containing the chat UI or empty.
