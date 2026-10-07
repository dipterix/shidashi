# Click a page element for an agent

Asks the browser to click the first element that matches `selector`, for
a tool call made by an agent (for example over `MCP`). The browser does
not click an element inside `[mcp-agent-disabled="true"]`: such controls
are for people only (for example a button that overwrites files), and
agents should ask the user to click them. People's own clicks are not
affected. Use this function in tools instead of sending the
`"shidashi.click"` message.

## Usage

``` r
mcp_click(
  selector,
  session = shiny::getDefaultReactiveDomain(),
  timeout = getOption("shidashi.click_timeout", 10)
)
```

## Arguments

- selector:

  CSS selector of the element to click

- session:

  shiny session; for modules, the module session

- timeout:

  seconds to wait for the browser's answer

## Value

A promise resolved with a list: `matched` (an element matched the
selector), `clicked`, `refused` (the element is disabled for agents),
and `note` (an invalid selector, for example). The promise is rejected
when the browser does not answer in time.

## Examples

``` r

# In a tool function (shiny session required):
# promises::then(mcp_click("#my_button", session), function(res) {
#   if (isTRUE(res$refused)) stop("The button is for people only")
#   "Clicked"
# })
```
