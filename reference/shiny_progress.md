# Wrapper of shiny progress that can run without shiny

Wrapper of shiny progress that can run without shiny

## Usage

``` r
shiny_progress(
  title,
  max = 1,
  ...,
  quiet = FALSE,
  session = shiny::getDefaultReactiveDomain(),
  shiny_auto_close = FALSE,
  log = NULL,
  outputId = NULL
)
```

## Arguments

- title:

  the title of the progress

- max:

  max steps of the procedure

- ...:

  passed to initialization method of
  [`Progress`](https://rdrr.io/pkg/shiny/man/Progress.html)

- quiet:

  whether the progress needs to be quiet

- session:

  shiny session domain

- shiny_auto_close:

  whether to close the progress once function exits

- log:

  alternative log function

- outputId:

  the element id of
  [`progressOutput`](https://dipterix.org/shidashi/reference/progressOutput.md),
  or `NULL` to use the default shiny progress

## Value

a list of functions that controls the progress

## Examples

``` r
{
  progress <- shiny_progress("Procedure A", max = 10)
  for(i in 1:10){
    progress$inc(sprintf("Step %s", i))
    Sys.sleep(0.1)
  }
  progress$close()

}
#> [Procedure A]: initializing...                                                  
#> [Procedure A]: Step 1 (1 out of 10)                                             
#> [Procedure A]: Step 2 (2 out of 10)                                             
#> [Procedure A]: Step 3 (3 out of 10)                                             
#> [Procedure A]: Step 4 (4 out of 10)                                             
#> [Procedure A]: Step 5 (5 out of 10)                                             
#> [Procedure A]: Step 6 (6 out of 10)                                             
#> [Procedure A]: Step 7 (7 out of 10)                                             
#> [Procedure A]: Step 8 (8 out of 10)                                             
#> [Procedure A]: Step 9 (9 out of 10)                                             
#> [Procedure A]: Step 10 (10 out of 10)                                           
#> Finished                                                                        

if(interactive()){
  library(shiny)

  ui <- fluidPage(
    fluidRow(
      column(12, actionButton("click", "Click me"))
    )
  )

  server <- function(input, output, session) {
    observeEvent(input$click, {
      progress <- shiny_progress("Procedure B", max = 10,
                                 shiny_auto_close = TRUE)
      for(i in 1:10){
        progress$inc(sprintf("Step %s", i))
        Sys.sleep(0.1)
      }
    })
  }

  shinyApp(ui, server)
}
```
