# Generates badge icons

Usually used along with
[`card`](https://dipterix.org/shidashi/reference/card.md),
[`card2`](https://dipterix.org/shidashi/reference/card.md), and
[`card_tabset`](https://dipterix.org/shidashi/reference/card_tabset.md).
See `tools` parameters in these functions accordingly.

## Usage

``` r
as_badge(badge = NULL)
```

## Arguments

- badge:

  characters, `"shiny.tag"` object or `NULL`

## Value

'HTML' tags

## Details

When `badge` is `NULL` or empty, then `as_badge` returns empty strings.
When `badge` is a `"shiny.tag"` object, then 'HTML' class `'right'` and
`'badge'` will be appended. When `badge` is a string, it should follow
the syntax of `"message|class"`. The text before `"|"` will be the badge
message, and the text after the `"|"` becomes the class string.

## Examples

``` r
# Basic usage
as_badge("New")
#> <span class="right badge">New</span>

# Add class `bg-red` and `no-padding`
as_badge("New|bg-red no-padding")
#> <span class="right badge bg-red no-padding">New</span>

```
