# Obtain the module information

Obtain the module information

## Usage

``` r
module_info(root_path = template_root(), settings_file = "modules.yaml")

load_module(
  root_path = template_root(),
  request = list(QUERY_STRING = "/"),
  env = parent.frame()
)
```

## Arguments

- root_path:

  the root path of the website project

- settings_file:

  the settings file containing the module information

- request:

  'HTTP' request string

- env:

  environment to load module variables into

## Value

A data frame with the following columns that contain the module
information:

- `id`:

  module id, folder name

- `order`:

  display order in side-bar

- `group`:

  group menu name if applicable, otherwise `NA`

- `label`:

  the readable label to be displayed on the side-bar

- `icon`:

  icon that will be displayed ahead of label, will be passed to
  [`as_icon`](https://dipterix.org/shidashi/reference/as_icon.md)

- `badge`:

  badge text that will be displayed following the module label, will be
  passed to
  [`as_badge`](https://dipterix.org/shidashi/reference/as_badge.md)

- `url`:

  the relative 'URL' address of the module.

## Details

The module files are stored in `modules/` folder in your project. The
folder names are the module id. Within each folder, there should be one
`"server.R"`, `R/`, and a `"module-ui.html"`.

The `R/` folder stores R code files that generate variables, which will
be available to the other two files. These variables, along with some
built-ins, will be used to render `"module-ui.html"`. The built-in
functions are

- ns:

  shiny name-space function; should be used to generate the id for
  inputs and outputs. This strategy avoids conflict id effectively.

- .module_id:

  a variable of the module id

- module_title:

  a function that returns the module label

The `"server.R"` has access to all the code in `R/` as well. Therefore
it is highly recommended that you write each 'UI' component side-by-side
with their corresponding server functions and call these server
functions in `"server.R"`.

## Examples

``` r
library(shiny)
module_info()
#>              id group          label                 icon      badge
#> 1    getstarted  <NA>    Get Started               rocket           
#> 2          card Cards          Cards               square           
#> 3       widgets Cards        Widgets         puzzle-piece           
#> 4          demo  <NA>           Demo            chart-bar           
#> 5 filestructure  <NA> File Structure          folder-open           
#> 6       page500  <NA>      Error 500 exclamation-triangle           
#> 7     module_id  <NA>   Module Label               circle New|bg-red
#>                      url
#> 1    /?module=getstarted
#> 2          /?module=card
#> 3       /?module=widgets
#> 4          /?module=demo
#> 5 /?module=filestructure
#> 6       /?module=page500
#> 7     /?module=module_id

# load master module
load_module()
#> $environment
#> <environment: 0x55944c2612c0>
#> 
#> $has_module
#> [1] FALSE
#> 
#> $root_path
#> [1] "/home/runner/.local/share/R/shidashi/bslib-bare"
#> 
#> $template_path
#> [1] "/home/runner/.local/share/R/shidashi/bslib-bare/index.html"
#> 
#> $module
#> $module$id
#> NULL
#> 
#> $module$server
#> function (input, output, session, ...) 
#> {
#> }
#> <bytecode: 0x55944a2e1be0>
#> <environment: 0x55944a2dfac8>
#> 
#> $module$template_path
#> NULL
#> 
#> 

# load specific module
module_data <- load_module(
  request = list(QUERY_STRING = "/?module=module_id"))
env <- module_data$environment

if(interactive()){

# get module title
env$module_title()

# generate module-specific shiny id
env$ns("input1")

# generate part of the UI
env$ui()

}
```
