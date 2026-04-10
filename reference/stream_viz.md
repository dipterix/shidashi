# Create a streaming widget

Creates a multi-channel signal viewer widget that fetches its data from
the binary stream file produced by
[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md).

## Usage

``` r
stream_viz(
  outputId,
  session = shiny::getDefaultReactiveDomain(),
  stream_id = NULL,
  width = NULL,
  height = NULL,
  refresh_rate = 33,
  show_controls = TRUE,
  streaming = FALSE,
  token = NULL
)
```

## Arguments

- outputId:

  Character scalar. The output ID matching the corresponding
  [`streamVizOutput`](https://dipterix.org/shidashi/reference/streamVizOutput.md)
  call. Used to compute `stream_id` automatically when `stream_id` is
  `NULL`.

- session:

  Shiny session object. Defaults to the active reactive domain. Together
  with `outputId` determines the token-qualified stream file identifier.

- stream_id:

  Character scalar or `NULL`. When `NULL` (default) the stream
  identifier is computed as
  `stream_file_id(outputId, session, token = token)`. Provide an
  explicit value to override for non-Shiny or advanced use.

- width, height:

  Widget dimensions (passed to
  [`createWidget`](https://rdrr.io/pkg/htmlwidgets/man/createWidget.html)).

- refresh_rate:

  Numeric scalar (milliseconds). Polling interval used when the viewer
  is in *active streaming* mode (play button pressed). Lower values give
  smoother animation but increase CPU/network load. Default `33`
  (approximately 30 Hz).

- show_controls:

  Logical. Whether to display the hover toolbar (play/pause, zoom,
  reset, export). Default `TRUE`.

- streaming:

  Logical. Whether to start active streaming immediately when the widget
  is rendered. Default `FALSE`; set to `TRUE` to begin polling for new
  data automatically. Can also be toggled later via
  [`updateStreamViz`](https://dipterix.org/shidashi/reference/updateStreamViz.md).

- token:

  Character scalar or `NULL`. When `NULL` (default) the session's own
  token is used. Override with a parent session token when running
  inside a standalone viewer (pop-out window) so that the child session
  fetches the parent's binary stream file.

## Value

An htmlwidgets object.

## Details

The `outputId` together with `session` is used to auto-compute the
token-qualified stream file identifier via
[`stream_file_id`](https://dipterix.org/shidashi/reference/stream_file_id.md).
You can override this by passing an explicit `stream_id`.

Use
[`updateStreamViz`](https://dipterix.org/shidashi/reference/updateStreamViz.md)
for in-place updates without recreating the widget.

## See also

[`streamVizOutput`](https://dipterix.org/shidashi/reference/streamVizOutput.md),
[`renderStreamViz`](https://dipterix.org/shidashi/reference/renderStreamViz.md),
[`updateStreamViz`](https://dipterix.org/shidashi/reference/updateStreamViz.md),
[`stream_file_id`](https://dipterix.org/shidashi/reference/stream_file_id.md)
