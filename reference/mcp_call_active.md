# Whether an `MCP` tool call is running

Returns `TRUE` while a tool runs for an `MCP` request, and `FALSE`
otherwise, for example when the in-dashboard chat calls the same tool.
While it is `TRUE`, the environment variable `SHIDASHI_USING_MCP` is set
to `"TRUE"`, so code that cannot call this function, such as skill
scripts running in their own process, can check the variable instead.

## Usage

``` r
mcp_call_active(v)
```

## Arguments

- v:

  optional logical; when given, turns the state on (`TRUE`) or off
  (anything else), and sets or removes `SHIDASHI_USING_MCP` to match.
  App code normally only reads the state.

## Value

`TRUE` or `FALSE`: the state after any change.

## Details

The dashboard's `MCP` handler turns the state on before each tool call
and off when the call returns, also when the tool fails. A tool that
returns a promise returns before the promise settles, so code that runs
once it settles sees `FALSE`.

## Examples

``` r
# Outside of an MCP tool call
mcp_call_active()
#> [1] FALSE
Sys.getenv("SHIDASHI_USING_MCP")
#> [1] ""

# In a tool: print less when an agent calls it over MCP
summarize_values <- function(x) {
  if (!mcp_call_active()) {
    message("Summarizing ", length(x), " values")
  }
  summary(x)
}
summarize_values(1:10)
#> Summarizing 10 values
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>    1.00    3.25    5.50    5.50    7.75   10.00 
```
