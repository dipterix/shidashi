# Open a URL in a new browser tab

Sends a message to the client to open the specified URL in a new browser
window/tab.

## Usage

``` r
open_url(url, target = "_blank", session = shiny::getDefaultReactiveDomain())
```

## Arguments

- url:

  character string, the URL to open

- target:

  the `window.open` target; default is `"_blank"` (new tab)

- session:

  shiny session

## Value

No value is returned (called for side effect).
