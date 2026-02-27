# Get Bootstrap 5 dependencies via bslib

Returns Bootstrap 5 HTML dependencies provided by bslib. Intended to be
called from HTML templates so that `headContent()` renders Bootstrap 5
CSS and JavaScript.

## Usage

``` r
bslib_dependency(...)
```

## Arguments

- ...:

  additional arguments passed to
  [`bslib::bs_theme`](https://rstudio.github.io/bslib/reference/bs_theme.html)

## Value

An
[`htmltools::tagList`](https://rstudio.github.io/htmltools/reference/tagList.html)
containing Bootstrap 5 dependencies
