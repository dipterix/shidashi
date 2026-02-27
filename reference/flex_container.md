# Generate 'HTML' tags with 'flex' layout

Generate 'HTML' tags with 'flex' layout

## Usage

``` r
flex_container(
  ...,
  style = NULL,
  direction = c("row", "column"),
  wrap = c("wrap", "nowrap", "wrap-reverse"),
  justify = c("flex-start", "center", "flex-end", "space-around", "space-between"),
  align_box = c("stretch", "flex-start", "center", "flex-end", "baseline"),
  align_content = c("stretch", "flex-start", "flex-end", "space-between", "space-around",
    "center")
)

flex_item(
  ...,
  size = 1,
  style = NULL,
  order = NULL,
  flex = as.character(size),
  align = c("flex-start", "flex-end", "center"),
  class = NULL,
  .class = "fill-width padding-5"
)

flex_break(..., class = NULL)
```

## Arguments

- ...:

  for `flex_container`, it's elements of `flex_item`; for `flex_item`,
  `...` are shiny 'HTML' tags

- style:

  the additional 'CSS' style for containers or inner items

- direction, wrap, justify, align_box, align_content:

  'CSS' styles for 'flex' containers

- size:

  numerical relative size of the item; will be ignored if `flex` is
  provided

- order, align, flex:

  CSS' styles for 'flex' items

- class, .class:

  class to add to the elements

## Value

'HTML' tags

## Examples

``` r
x <- flex_container(
  style = "position:absolute;height:100vh;top:0;left:0;width:100%",
  flex_item(style = 'background-color:black;'),
  flex_item(style = 'background-color:red;')
)
# You can view it via `htmltools::html_print(x)`
```
