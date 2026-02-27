# Template function to include 'snippets' in the view folder

Store the reusing 'HTML' segments in the `views` folder. This function
should be used in the `'index.html'` template

## Usage

``` r
include_view(file, ..., .env = parent.frame(), .root_path = template_root())
```

## Arguments

- file:

  files in the template `views` folder

- ...:

  ignored

- .env, .root_path:

  internally used

## Value

rendered 'HTML' segments

## Examples
