# Generates 'AdminLTE' theme-related 'HTML' tags

These functions should be called in 'HTML' templates. Please see
vignettes for details.

## Usage

``` r
adminlte_ui(root_path = template_root())

adminlte_sidebar(
  root_path = template_root(),
  settings_file = "modules.yaml",
  shared_id = rand_string(26)
)
```

## Arguments

- root_path:

  the root path of the website project; see
  [`template_settings`](https://dipterix.org/shidashi/reference/template_settings.md)

- settings_file:

  the settings file containing the module information

- shared_id:

  a shared identification by session to synchronize the inputs; assigned
  internally.

## Value

'HTML' tags
