# Generates outputs that can be written to clipboards with one click

Generates outputs that can be written to clipboards with one click

## Usage

``` r
clipboardOutput(
  outputId = rand_string(prefix = "clipboard"),
  message = "Copy to clipboard",
  clip_text = "",
  class = NULL,
  as_card_tool = FALSE
)

renderClipboard(
  expr,
  env = parent.frame(),
  quoted = FALSE,
  outputArgs = list()
)
```

## Arguments

- outputId:

  the output id

- message:

  tool tip to show when mouse hovers on the element

- clip_text:

  the initial text to copy to clipboards

- class:

  'HTML' class of the element

- as_card_tool:

  whether to make the output as
  [`card_tool`](https://dipterix.org/shidashi/reference/card_tool.md)

- expr:

  expression to evaluate; the results will replace `clip_text`

- env:

  environment to evaluate `expr`

- quoted:

  whether `expr` is quoted

- outputArgs:

  used to replace default arguments of `clipboardOutput`

## Value

'HTML' elements that can write to clip-board once users click on them.

## Examples

``` r
clipboardOutput(clip_text = "Hey there")
#> <div id="clipboardomb92Q9Qeu" class="shidashi-clipboard-output">
#>   <button class="clipboard-btn btn btn-default" data-clipboard-text="Hey there" role="button">Copy to clipboard</button>
#> </div>
```
