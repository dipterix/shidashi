# Configure template options that are shared across the sessions

Configure template options that are shared across the sessions

## Usage

``` r
template_settings

template_settings_set(...)

template_settings_get(name, default = NULL)

template_root()
```

## Format

An object of class `list` of length 3.

## Arguments

- ...:

  key-value pair to set options

- name:

  character, key of the value

- default:

  default value if the key is missing

## Value

`template_settings_get` returns the values represented by the
corresponding keys, or the default value if key is missing.

## Details

The settings is designed to store static key-value pairs that are shared
across the sessions. The most important key is `"root_path"`, which
should be a path pointing to the template folder.

## Examples

``` r
# Get current website root path

template_root()
#> [1] "/home/runner/.local/share/R/shidashi/bslib-bare"
```
