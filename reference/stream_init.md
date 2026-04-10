# Initialize the shidashi stream directory for a Shiny session

Call once in the server function to set up the directory that
[`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md)
and
[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md)
will write to. When running inside a shidashi template the directory is
automatically resolved from the template root; when running in plain
Shiny a temporary directory is created and registered with
[`addResourcePath`](https://rdrr.io/pkg/shiny/man/resourcePaths.html) so
that the browser can fetch `stream/{token}_{id}.bin`. An optional
cleanup hook is registered to remove this session's files when the
session ends.

## Usage

``` r
stream_init(session = shiny::getDefaultReactiveDomain())
```

## Arguments

- session:

  Shiny session object. Defaults to the currently active reactive
  domain.

## Value

Invisibly returns the absolute path to the stream directory.

## See also

[`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md),
[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md)
