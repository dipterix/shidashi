# A Shiny Template System

<!-- badges: start -->
[![R-CMD-check](https://github.com/dipterix/shidashi/workflows/R-CMD-check/badge.svg)](https://github.com/dipterix/shidashi/actions)
[![CRAN status](https://www.r-pkg.org/badges/version/shidashi)](https://CRAN.R-project.org/package=shidashi)
<!-- badges: end -->

The goal of shidashi is to provide framework for R-shiny templates, especially for dashboard applications.

<div>
<img src="https://raw.githubusercontent.com/dipterix/shidashi/main/inst/screenshots/theme-light.png" width="45%">
<img src="https://raw.githubusercontent.com/dipterix/shidashi/main/inst/screenshots/theme-dark.png" width="45%">
<small>
*Default template (using [AdminLTE](https://adminlte.io/)) provides two themes: light vs dark*
</small>
</div>

## Installation

You can install the released version of shidashi from [CRAN](https://CRAN.R-project.org) with:

``` r
install.packages("shidashi")
```

## Demo Application

You can view the demo app via R command

``` r
library(shidashi)
temp_project <- tempfile()
use_template(temp_project)
render(temp_project)
```

## Start From Existing Templates

To start a `shidashi` project, open `RStudio` menu from the navigation bar:

> File > New Project... > New Directory > Shidashi Shiny Template (*)

_*You might need to scroll down to find that template option_.

Please enter the project information accordingly. By default, the `Github user` is `dipterix`, and theme is `AdminLTE3`, which lead to [the default template](https://github.com/dipterix/shidashi-templates/tree/master/AdminLTE3).

##### Bare-bone Template

If you want to start from a bare-bone template, change the `theme` option to be `AdminLTE3-bare`.

### File Structure

A typical `shidashi` project has the following file structure:

```
<project root_path>
├─modules/
│ └─<module ID> . . . . . - Module folder; folder name is module ID
│   ├─R . . . . . . . . . - Module functions shared across UI and server
│   ├─module-ui.html  . . - Module HTML template
│   └─server.R  . . . . . - Module-level server function
├─R/  . . . . . . . . . . - Common functions shared across modules
├─views/. . . . . . . . . - Small snippets (see `?include_view` function)
├─www/  . . . . . . . . . - Static files: css, js, img, ...
├─index.html  . . . . . . - Template for homepage
├─modules.yaml  . . . . . - Module label, order, icon, badge..
└─server.R  . . . . . . . - Root server function, usually no modification is required
```

## Contribute

Create your own `Github` repository with name `shidashi-templates`. Add folders named by the themes. Then people can install your themes as templates through `RStudio`.
An easy start is to fork [this repository](https://github.com/dipterix/shidashi-templates/)
