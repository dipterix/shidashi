# Generates small icon widgets

The icons cane be displayed at header line within
[`accordion`](https://dipterix.org/shidashi/reference/accordion.md),
[`card`](https://dipterix.org/shidashi/reference/card.md),
[`card2`](https://dipterix.org/shidashi/reference/card.md),
[`card_tabset`](https://dipterix.org/shidashi/reference/card_tabset.md).
See their examples.

## Usage

``` r
card_tool(
  inputId = NULL,
  title = NULL,
  widget = c("maximize", "collapse", "remove", "flip", "refresh", "link", "custom"),
  icon,
  class = "",
  href = "#",
  target = "_blank",
  start_collapsed = FALSE,
  ...
)
```

## Arguments

- inputId:

  the button id, only necessary when `widget` is `"custom"`

- title:

  the tip message to show when the mouse cursor hovers on the icon

- widget:

  the icon widget type; choices are `"maximize"`, `"collapse"`,
  `"remove"`, `"flip"`, `"refresh"`, `"link"`, and `"custom"`; see
  'Details'

- icon:

  icon to use if you are unsatisfied with the default ones

- class:

  additional class for the tool icons

- href, target:

  used when `widget` is `"link"`, will open an external website; default
  is open a new tab

- start_collapsed:

  used when `widget` is `"collapse"`, whether the card should start
  collapsed

- ...:

  passed to the tag as attributes

## Value

'HTML' tags to be included in `tools` parameter in
[`accordion`](https://dipterix.org/shidashi/reference/accordion.md),
[`card`](https://dipterix.org/shidashi/reference/card.md),
[`card2`](https://dipterix.org/shidashi/reference/card.md),
[`card_tabset`](https://dipterix.org/shidashi/reference/card_tabset.md)

## Details

There are 7 `widget` types:

- `"maximize"`:

  allow the elements to maximize themselves to full-screen

- `"collapse"`:

  allow the elements to collapse

- `"remove"`:

  remove a [`card`](https://dipterix.org/shidashi/reference/card.md) or
  [`card2`](https://dipterix.org/shidashi/reference/card.md)

- `"flip"`:

  used together with
  [`flip_box`](https://dipterix.org/shidashi/reference/flip_box.md), to
  allow card body to flip over

- `"refresh"`:

  refresh all shiny outputs

- `"link"`:

  open a hyper-link pointing to external websites

- `"custom"`:

  turn the icon into a `actionButton`. in this case, `inputId` must be
  specified.
