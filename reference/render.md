# Render a 'shidashi' project

Render a 'shidashi' project

## Usage

``` r
render(
  root_path = template_root(),
  ...,
  prelaunch = NULL,
  prelaunch_quoted = FALSE,
  launch_browser = TRUE,
  as_job = TRUE,
  test_mode = getOption("shiny.testmode", FALSE)
)
```

## Arguments

- root_path:

  the project path, default is the demo folder from
  [`template_root()`](https://dipterix.org/shidashi/reference/template_settings.md)

- ...:

  additional parameters passed to
  [`runApp`](https://rdrr.io/pkg/shiny/man/runApp.html), such as `host`,
  `port`

- prelaunch:

  expression to execute before launching the session; the expression
  will execute in a brand new session

- prelaunch_quoted:

  whether the expression is quoted; default is false

- launch_browser:

  whether to launch browser; default is `TRUE`

- as_job:

  whether to run as 'RStudio' jobs; this options is only available when
  'RStudio' is available

- test_mode:

  whether to test the project; this options is helpful when you want to
  debug the project without relaunching shiny applications

## Value

This functions runs a 'shiny' application, and returns the job id if
'RStudio' is available.

## Examples

``` r
template_root()
#> [1] "/home/runner/.local/share/R/shidashi/bslib-bare"

if(interactive()){
  render()
}
```
