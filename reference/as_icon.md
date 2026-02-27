# Convert characters, shiny icons into 'fontawesome' 4

Convert characters, shiny icons into 'fontawesome' 4

## Usage

``` r
as_icon(icon = NULL, class = "fas")
```

## Arguments

- icon:

  character or [`icon`](https://rdrr.io/pkg/shiny/man/icon.html)

- class:

  icon class; change this when you are using 'fontawesome' professional
  version. The choices are `'fa'` (compatible), `'fas'` (strong),
  `'far'` (regular), `'fal'` (light), and `'fad'` (duo-tone).

## Value

'HTML' tag

## Examples

``` r
if(interactive()){
as_icon("bookmark", class = "far")
as_icon("bookmark", class = "fas")

# no icon
as_icon(NULL)
}
```
