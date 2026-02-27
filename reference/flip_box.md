# An 'HTML' container that can flip

An 'HTML' container that can flip

## Usage

``` r
flip_box(
  front,
  back,
  active_on = c("click", "click-front", "manual"),
  inputId = NULL,
  class = NULL
)

flip(inputId, session = shiny::getDefaultReactiveDomain())
```

## Arguments

- front:

  'HTML' elements to show in the front

- back:

  'HTML' elements to show when the box is flipped

- active_on:

  the condition when a box should be flipped; choices are `'click'`:
  flip when double-click on both sides; `'click-front'`: only flip when
  the front face is double-clicked; `'manual'`: manually flip in `R`
  code (see `{flip(inputId)}` function)

- inputId:

  element 'HTML' id; must be specified if `active_on` is not `'click'`

- class:

  'HTML' class

- session:

  shiny session; default is current active domain

## Value

`flip_box` returns 'HTML' tags; `flip` should be called from shiny
session, and returns nothing

## Examples

``` r
# More examples are available in demo

library(shiny)
library(shidashi)

session <- MockShinySession$new()

flip_box(front = info_box("Side A"),
         back = info_box("Side B"),
         inputId = 'flip_box1')
#> <div class="flip-box" data-toggle="click" data-bs-toggle="click" id="flip_box1">
#>   <div class="flip-box-inner">
#>     <div class="flip-box-back"><div class="info-box ">
#>   <span class="info-box-icon bg-info">
#>         <i class="far fa-envelope fas" role="presentation" aria-label="envelope icon"></i>
#>       </span>
#>   <div class="info-box-content ">
#>     Side B
#>   </div>
#> </div>
#> </div>
#>     <div class="flip-box-front"><div class="info-box ">
#>   <span class="info-box-icon bg-info">
#>         <i class="far fa-envelope fas" role="presentation" aria-label="envelope icon"></i>
#>       </span>
#>   <div class="info-box-content ">
#>     Side A
#>   </div>
#> </div>
#> </div>
#>   </div>
#> </div>

flip('flip_box1', session = session)
```
