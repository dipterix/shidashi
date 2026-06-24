# Write data to a shidashi stream binary file

Serializes `data` together with a JSON header into the binary envelope
expected by the JavaScript `window.shidashi.fetchStreamData(id)` method.

## Usage

``` r
stream_to_js(
  abspath,
  data,
  type = c("raw", "json", "int32", "float32", "float64"),
  ...
)
```

## Arguments

- abspath:

  Character scalar. Absolute path to the target `.bin` file. Use
  [`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md)`(id)`
  to obtain a path under the app's `www/stream/` directory.

- data:

  The data to serialize. See Details for how each `type` interprets this
  argument.

- type:

  Character scalar. One of `"raw"`, `"json"`, `"int32"`, `"float32"`, or
  `"float64"`.

- ...:

  Additional named scalar values to embed in the JSON header and expose
  to the JavaScript caller via `result.header`.

## Value

Invisibly returns `abspath`.

## Details

**Wire format**


      [endianFlag: 1 byte]  [headerLen: uint32 LE]  [header: UTF-8 JSON]  [body]

`endianFlag` is always `0x01` (little-endian). `header` is a JSON object
containing at minimum `data_type` plus any extra fields passed via
`...`.

**Body encoding by type**

- `"raw"`:

  Passed through verbatim; `data` must be a `raw` vector or will be
  coerced via [`as.raw()`](https://rdrr.io/r/base/raw.html).

- `"json"`:

  `data` is serialized with `jsonlite::toJSON(auto_unbox = TRUE)`.

- `"int32"`:

  `data` is coerced to integer and written as 4-byte little-endian
  signed integers.

- `"float32"`:

  `data` is coerced to double and written as 4-byte little-endian IEEE
  754 single-precision floats.

- `"float64"`:

  `data` is coerced to double and written as 8-byte little-endian IEEE
  754 double-precision floats.

## See also

[`stream_path`](https://dipterix.org/shidashi/reference/stream_path.md)
