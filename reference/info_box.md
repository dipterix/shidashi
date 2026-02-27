# Generates 'HTML' info box

Generates 'HTML' info box

## Usage

``` r
info_box(
  ...,
  icon = "envelope",
  class = "",
  class_icon = "bg-info",
  class_content = "",
  root_path = template_root()
)
```

## Arguments

- ...:

  box content

- icon:

  the box icon; default is `"envelope"`, can be hidden by specifying
  `NULL`

- class:

  class of the box container

- class_icon:

  class of the icon

- class_content:

  class of the box body

- root_path:

  see
  [`template_root`](https://dipterix.org/shidashi/reference/template_settings.md)

## Value

'HTML' tags

## Examples

``` r
library(shiny)
library(shidashi)

info_box("Message", icon = "cogs")
#> <div class="info-box ">
#>   <span class="info-box-icon bg-info">
#>   <i class="fas fa-gears" role="presentation" aria-label="gears icon"></i>
#> </span>
#>   <div class="info-box-content ">
#>     Message
#>   </div>
#> </div>
#> 

info_box(
  icon = "thumbs-up",
  span(class = "info-box-text", "Likes"),
  span(class = "info-box-number", "12,320"),
  class_icon = "bg-red"
)
#> <div class="info-box ">
#>   <span class="info-box-icon bg-red">
#>   <i class="far fa-thumbs-up fas" role="presentation" aria-label="thumbs-up icon"></i>
#> </span>
#>   <div class="info-box-content ">
#>     <span class="info-box-text">Likes</span>
#> <span class="info-box-number">12,320</span>
#>   </div>
#> </div>
#> 

info_box("No icons", icon = NULL)
#> <div class="info-box ">
#>   
#>   <div class="info-box-content ">
#>     No icons
#>   </div>
#> </div>
#> 
```
