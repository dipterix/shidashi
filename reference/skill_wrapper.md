# Wrap a Skill Directory as an `MCP` Tool Generator

Creates a closure that produces an
[`ellmer::tool`](https://ellmer.tidyverse.org/reference/tool.html)
dispatching on an `action` enumerator:

- `readme`:

  Returns the full `SKILL.md` instructions. Must be called first to
  unlock other actions.

- `reference`:

  Returns content from a reference file in the skill directory (gated
  behind `readme`).

- `script`:

  Executes a script in the `scripts/` subdirectory via
  [`processx::run()`](http://processx.r-lib.org/reference/run.md) (gated
  behind `readme`).

## Usage

``` r
skill_wrapper(skill_path)
```

## Arguments

- skill_path:

  Path to the skill directory containing `SKILL.md`. Can be absolute or
  relative to the project root.

## Value

A function with class `c("shidashi_skill_wrapper", "function")` that
returns an
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/ToolDef.html)
object.

## Details

The returned tool enforces a soft gate: calling `reference` or `script`
before `readme` is allowed, but if the call errors the message is
augmented with a condensed summary (~200 tokens) instructing the AI to
read the full instructions first. This minimizes token waste (the
summary is only sent on failure).

The gate state is per-instance: each call to the wrapper produces a
closure with an independent `readme_unlocked` flag.

## Examples

``` r
skill_dir <- system.file(
  "builtin-templates/bslib-bare/agents/skills/greet",
  package = "shidashi"
)
wrapper  <- skill_wrapper(skill_dir)
tool_def <- wrapper()
cat(tool_def(action = "readme"))
#> ## Instructions
#> 
#> This skill demonstrates the skill system. It runs a short R script
#> that prints a personalised greeting.
#> 
#> ### Usage
#> 
#> 1. Call `action='script'`, `file_name='greet.R'`, `args=['World']`
#> 2. The script prints: `Hello, World!`
#> 
#> ### Arguments
#> 
#> - `args[1]`: The name to greet (default: `"World"`)
#> 
#> ## Available scripts
#> - greet.R
```
