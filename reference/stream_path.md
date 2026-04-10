# Get the absolute path for a shidashi stream file

Returns the full path to the binary file that will be served at
`stream/{token}_{id}.bin`. The filename embeds the session token so that
simultaneous Shiny sessions never overwrite each other's data. Call
[`stream_init`](https://dipterix.org/shidashi/reference/stream_init.md)
at least once per session before relying on this function.

## Usage

``` r
stream_path(id, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- id:

  Character scalar. Stream identifier. Must be a valid file-name
  component (no path separators).

- session:

  Shiny session object. Defaults to the currently active reactive
  domain.

## Value

Invisible character scalar: absolute path to the `.bin` file.

## See also

[`stream_init`](https://dipterix.org/shidashi/reference/stream_init.md),
[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md)
