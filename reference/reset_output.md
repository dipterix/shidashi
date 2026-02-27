# Reset shiny outputs with messages

Forces outdated output to reset and show a silent message.

## Usage

``` r
reset_output(
  outputId,
  message = "This output has been reset",
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- outputId:

  output ID

- message:

  output message

- session:

  shiny reactive domain

## Value

No value
