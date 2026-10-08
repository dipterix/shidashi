# Report session state to agents

Registers a value that the `MCP` tool `shiny_input_info` reports next to
the inputs, under the key `"@state"`. Use it for state that changes what
an agent should ask, for example whether the data loader is open (a
closed loader usually means the data are loaded and the user wants to
change analysis inputs only).

## Usage

``` r
register_input_state(
  name,
  getter,
  description = "",
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- name:

  character string, the name of the state

- getter:

  a function without arguments that returns the current value; it is
  called in
  [`shiny::isolate()`](https://rdrr.io/pkg/shiny/man/isolate.html) each
  time `shiny_input_info` runs, and an error is reported as the state's
  `error` instead of failing the tool call

- description:

  character string: what the value means, for agents

- session:

  the `shiny` session (the module's session)

## Value

`NULL`, invisibly

## Examples

``` r
if (FALSE) { # \dontrun{
# in a module server function
register_input_state(
  "loader_opened",
  function() isTRUE(loader_is_open()),
  description = "TRUE while the data loader is open"
)
} # }
```
