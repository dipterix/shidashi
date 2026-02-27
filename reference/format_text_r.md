# Get re-formatted `R` expressions in characters

Get re-formatted `R` expressions in characters

## Usage

``` r
format_text_r(
  expr,
  quoted = FALSE,
  reformat = TRUE,
  width.cutoff = 80L,
  indent = 2,
  wrap = TRUE,
  args.newline = TRUE,
  blank = FALSE,
  ...
)

html_highlight_code(
  expr,
  class = NULL,
  quoted = FALSE,
  reformat = TRUE,
  copy_on_click = TRUE,
  width.cutoff = 80L,
  indent = 2,
  wrap = TRUE,
  args.newline = TRUE,
  blank = FALSE,
  ...,
  hover = c("overflow-visible-on-hover", "overflow-auto")
)
```

## Arguments

- expr:

  `R` expressions

- quoted:

  whether `expr` is quoted

- reformat:

  whether to reformat

- width.cutoff, indent, wrap, args.newline, blank, ...:

  passed to
  [`tidy_source`](https://rdrr.io/pkg/formatR/man/tidy_source.html)

- class:

  class of `<pre>` tag

- copy_on_click:

  whether to copy to clipboard if user clicks on the code; default is
  true

- hover:

  mouse hover behavior

## Value

`format_text_r` returns characters, `html_highlight_code` returns the
'HTML' tags wrapping expressions in `<pre>` tag

## See also

[`get_construct_string`](https://dipterix.org/shidashi/reference/get_construct_string.md)

## Examples

``` r
s <- format_text_r(print(local({a<-1;a+1})))
cat(s)
#> print(
#>   local(
#>     {
#>       a <- 1
#>       a + 1
#>     }
#>   )
#> )

x <- info_box("Message", icon = "cogs")
s <- format_text_r(get_construct_string(x),
                   width.cutoff = 15L, quoted = TRUE)
cat(s)
#> info_box(
#>   "Message", icon = "cogs"
#> )

```
