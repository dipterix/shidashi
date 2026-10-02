# Wrap a Skill Directory as `MCP` Tool Generators

Creates a closure that produces two
[`ellmer::tool`](https://ellmer.tidyverse.org/reference/tool.html)
objects for a skill:

- `skill_load__<name>`:

  Reads the skill. Its `action` argument is `readme` (the full
  `SKILL.md` instructions, the default) or `reference` (content from a
  reference file in the skill directory). It never changes anything.

- `skill_run__<name>`:

  Executes a script in the `scripts/` subdirectory via
  [`processx::run()`](http://processx.r-lib.org/reference/run.md). Only
  created when the skill has scripts.

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
returns a list with elements `load` (an
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/ToolDef.html))
and `run` (an
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/ToolDef.html),
or `NULL` when the skill has no scripts).

## Details

The two tools share a soft gate: reading a reference or running a script
before the `readme` is allowed, but if the call errors the message is
augmented with a condensed summary (~200 tokens) instructing the AI to
read the full instructions first. This minimizes token waste (the
summary is only sent on failure).

The gate state is per-instance: each call to the wrapper produces a pair
of tools with an independent `readme_unlocked` flag.

Scripts inherit the app's environment variables, plus the ones the
caller passes in `envs`. When an agent runs a script over `MCP`,
`SHIDASHI_USING_MCP` is `"TRUE"`; see
[`mcp_call_active`](https://dipterix.org/shidashi/reference/mcp_call_active.md).

## Examples

``` r
skill_dir <- system.file(
  "builtin-templates/bslib-bare/agents/skills/greet",
  package = "shidashi"
)
wrapper <- skill_wrapper(skill_dir)
tools <- wrapper()
cat(tools$load(action = "readme"))
#> ## Instructions
#> 
#> This skill demonstrates the skill system. It runs a short R script
#> that prints a personalised greeting.
#> 
#> ### Usage
#> 
#> 1. Call `skill_run__greet` with `file_name='greet.R'`, `args=['World']`
#> 2. The script prints: `Hello, World!`
#> 
#> ### Arguments
#> 
#> - `args[1]`: The name to greet (default: `"World"`)
#> 
#> ## Available scripts
#> Run them with `skill_run__greet`: `file_name` is the script, and `args` holds its arguments, one item per argument (`<x>` required, `[x]` optional).
#> - greet.R [name]
```
