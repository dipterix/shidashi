# Progress bar in shiny dashboard

For detailed usage, see demo application by running
[`render()`](https://dipterix.org/shidashi/reference/render.md).

## Usage

``` r
progressOutput(
  outputId,
  ...,
  description = "Initializing",
  width = "100%",
  class = "bg-primary",
  value = 0,
  size = c("md", "sm", "xs")
)

renderProgress(expr, env = parent.frame(), quoted = FALSE, outputArgs = list())
```

## Arguments

- outputId:

  the element id of the progress

- ...:

  extra elements on the top of the progress bar

- description:

  descriptive message below the progress bar

- width:

  width of the progress

- class:

  progress class, default is `"bg-primary"`

- value:

  initial value, ranging from 0 to 100; default is 0

- size:

  size of the progress bar; choices are `"md"`, `"sm"`, `"xs"`

- expr:

  R expression that should return a named list of `value` and
  `description`

- env:

  where to evaluate `expr`

- quoted:

  whether `expr` is quoted

- outputArgs:

  a list of other parameters in `progressOutput`

## Value

`progressOutput` returns 'HTML' tags containing progress bars that can
be rendered later via
[`shiny_progress`](https://dipterix.org/shidashi/reference/shiny_progress.md)
or `renderProgress`. `renderProgress` returns shiny render functions
internally.

## Examples

``` r
library(shiny)
library(shidashi)
progressOutput("sales_report_prog1",
               description = "6 days left!",
               "Add Products to Cart",
               span(class="float-end", "123/150"),
               value = 123/150 * 100)
#> <div class="shidashi-progress-output progress-group" id="sales_report_prog1" style="width: 100%;">
#>   Add Products to Cart
#>   <span class="float-end">123/150</span>
#>   <div class="progress progress-md">
#>     <div class="progress-bar bg-primary" style="width: 82%"></div>
#>   </div>
#>   <span class="progress-description progress-message">6 days left!</span>
#>   <span class="progress-description progress-error"></span>
#> </div>

# server function
server <- function(input, output, session, ...){
  output$sales_report_prog1 <- renderProgress({
    return(list(
      value = 140 / 150 * 100,
      description = "5 days left!"
    ))
  })
}
```
