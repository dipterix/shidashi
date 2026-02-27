# Download 'shidashi' templates from 'Github'

Download 'shidashi' templates from 'Github'

## Usage

``` r
use_template(
  path,
  user = "dipterix",
  theme = "AdminLTE3",
  repo = "shidashi-templates",
  branch = "main",
  ...
)
```

## Arguments

- path:

  the path to create 'shidashi' project

- user:

  'Github' user name

- theme:

  the theme to download

- repo:

  repository if the name is other than `'shidashi-templates'`

- branch:

  branch name if other than `'main'` or `'master'`

- ...:

  ignored

## Value

the target project path

## Details

To publish a 'shidashi' template, create a 'Github' repository called
`'shidashi-templates'`, or fork the [built-in
templates](https://github.com/dipterix/shidashi-templates). The `theme`
is the sub-folder of the template repository.

An easy way to use a template in your project is through the 'RStudio'
project widget. In the 'RStudio' navigation bar, go to "File" menu,
click on the "New Project..." button, select the "Create a new project"
option, and find the item that creates 'shidashi' templates. Use the
widget to set up template directory.
