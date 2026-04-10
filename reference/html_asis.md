# Escape HTML strings

Escape HTML strings so that they will be displayed 'as-is' in websites.

## Usage

``` r
html_asis(s, space = TRUE)
```

## Arguments

- s:

  characters

- space:

  whether to also escape white space, default is true.

## Value

An R string

## Examples

``` r
html_asis("<a><----> <b>")
#> &lt;a&gt;&lt;----&gt;&nbsp;&lt;b&gt;
```
