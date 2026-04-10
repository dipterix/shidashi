# Build the token-qualified stream file identifier

Combines `session$token` with `id` to produce the string used both by
[`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md)
(as the filename stem) and by the browser as the URL path component
under `stream/`.

## Usage

``` r
stream_file_id(id, session = shiny::getDefaultReactiveDomain(), token = NULL)
```

## Arguments

- id:

  Character scalar. The base stream identifier (no path separators).

- session:

  Shiny session object. Defaults to the active reactive domain.

- token:

  Character scalar or `NULL`. When `NULL` (default) the session's own
  token is used. Override with a parent session token so that a
  standalone viewer (child session) can address the parent's binary
  stream file.

## Value

Character scalar: `"{token}_{id}"`.

## See also

[`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md),
[`stream_viz`](https://dipterix.org/shidashi/reference/stream_viz.md),
[`updateStreamViz`](https://dipterix.org/shidashi/reference/updateStreamViz.md)
