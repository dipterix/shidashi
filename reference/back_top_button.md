# 'HTML' code to generate small back-to-top button

This function is a template function that should be called in 'HTML'
templates before closing the `"</body>"` tag.

## Usage

``` r
back_top_button(icon = "chevron-up", title = "Jump to")
```

## Arguments

- icon:

  the icon for back-to-top button

- title:

  the expanded menu title

## Value

'HTML' tags

## Examples

``` r
back_top_button()
#> <div class="back-to-top">
#>   <div class="btn-group dropup" role="group">
#>     <a type="button" class="btn btn-default btn-go-top border-right-1" href="#">
#>       <i class="fas fa-chevron-up" role="presentation" aria-label="chevron-up icon"></i>
#>     </a>
#>     <button type="button" class="btn btn-default dropdown-toggle dropdown-toggle-split border-left-1" data-toggle="dropdown" data-bs-toggle="dropdown" aria-haspopup="false" aria-expanded="false">
#>       <span class="sr-only visually-hidden">Dropdown-Open</span>
#>     </button>
#>     <div class="dropdown-menu dropdown-menu-end">
#>       <h6 class="dropdown-header">Jump to</h6>
#>     </div>
#>   </div>
#> </div>
back_top_button("rocket")
#> <div class="back-to-top">
#>   <div class="btn-group dropup" role="group">
#>     <a type="button" class="btn btn-default btn-go-top border-right-1" href="#">
#>       <i class="fas fa-rocket" role="presentation" aria-label="rocket icon"></i>
#>     </a>
#>     <button type="button" class="btn btn-default dropdown-toggle dropdown-toggle-split border-left-1" data-toggle="dropdown" data-bs-toggle="dropdown" aria-haspopup="false" aria-expanded="false">
#>       <span class="sr-only visually-hidden">Dropdown-Open</span>
#>     </button>
#>     <div class="dropdown-menu dropdown-menu-end">
#>       <h6 class="dropdown-header">Jump to</h6>
#>     </div>
#>   </div>
#> </div>
```
