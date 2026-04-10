# Read a shidashi stream binary file

Reads the binary envelope written by
[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md)
and returns the header and decoded body as a list.

## Usage

``` r
read_stream_vis(path)
```

## Arguments

- path:

  Character scalar. Absolute path to a `.bin` file produced by
  [`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md).

## Value

A list with components:

- `header`:

  Named list parsed from the JSON header (contains `data_type`,
  `signature`, `timestamp`, and any extra fields).

- `data`:

  Decoded body: a `raw` vector for `"raw"`, an R object for `"json"`, or
  a numeric/integer vector for `"int32"`, `"float32"`, `"float64"`.

## See also

[`stream_to_js`](https://dipterix.org/shidashi/reference/stream_to_js.md),
[`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md)
