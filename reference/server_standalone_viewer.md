# Server function for the standalone viewer module

Internal server function used by the `standalone_viewer` hidden module.
Retrieves the render function from the parent module session and assigns
it to the viewer's output.

## Usage

``` r
server_standalone_viewer(input, output, session, ...)
```

## Arguments

- input, output, session:

  Shiny module server arguments

- ...:

  ignored
