# Trigger an in-place update of a streaming widget

Sends a custom Shiny message that causes the browser to re-fetch the
binary stream file and re-render the signal viewer without tearing down
and recreating the widget. Call this after writing new data with
[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md).
The `outputId` is used both to locate the widget as the stream file
identifier — it must match the `id` passed to
[`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md).

## Usage

``` r
updateStreamViz(
  outputId,
  streaming = NULL,
  token = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- outputId:

  Character scalar. The output ID passed to
  [`streamVizOutput`](https://dipterix.org/shidashi/reference/streamVizOutput.md)
  (and to
  [`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md)).

- streaming:

  Logical or `NULL`. `TRUE` starts active streaming (the widget polls
  for new data via `requestAnimationFrame`); `FALSE` pauses it; `NULL`
  (default) leaves the current streaming state unchanged.

- token:

  Character scalar or `NULL`. When `NULL` (default) the session's own
  token is used. Override with a parent session token when running
  inside a standalone viewer (pop-out window) so that the child session
  fetches the parent's binary stream file.

- session:

  Shiny session object. Defaults to the active reactive domain.

## Value

Invisibly `NULL`.

## See also

[`streamVizOutput`](https://dipterix.org/shidashi/reference/streamVizOutput.md),
[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md),
[`stream_file_id`](https://dipterix.org/shidashi/reference/stream_file_id.md)
