---
name: greet
description: "Prints a personalized hello greeting message by running an R script with a user-provided name. Use when the user asks for a greeting, wants to test the skill system, or needs a simple R script example that prints a hello message."
---

## Instructions

Runs `greet.R` to print a personalized greeting. Demonstrates the shidashi skill system with a minimal R script.

### Usage

1. Invoke the skill with the name to greet:

```
action: "script"
file_name: "greet.R"
args: ["Alice"]
```

2. Output: `Hello, Alice!`

If no name is provided, defaults to `"World"`.

### Arguments

| Argument | Type | Default | Description |
|----------|------|---------|-------------|
| `args[1]` | string | `"World"` | The name to include in the greeting |

### Script Reference

The skill runs `scripts/greet.R`:

```r
args <- commandArgs(trailingOnly = TRUE)
name <- if (length(args) >= 1L) args[[1L]] else "World"
cat(sprintf("Hello, %s!\n", name))
```
