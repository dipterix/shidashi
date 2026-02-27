# 'Accordion' items

'Accordion' items

## Usage

``` r
accordion_item(
  title,
  ...,
  footer = NULL,
  class = "",
  collapsed = TRUE,
  parentId = rand_string(prefix = "accordion-"),
  itemId = rand_string(prefix = "accordion-item-"),
  style_header = NULL,
  style_body = NULL,
  root_path = template_root()
)
```

## Arguments

- title:

  character title to show in the header

- ...:

  body content

- footer:

  footer element, hidden if `NULL`

- class:

  the class of the item

- collapsed:

  whether collapsed at the beginning

- parentId:

  parent
  [`accordion`](https://dipterix.org/shidashi/reference/accordion.md) id

- itemId:

  the item id

- style_header, style_body:

  'CSS' style of item header and body

- root_path:

  see `template_root`

## Value

`'shiny.tag.list'` 'HTML' tags

## See also

[`accordion`](https://dipterix.org/shidashi/reference/accordion.md)
