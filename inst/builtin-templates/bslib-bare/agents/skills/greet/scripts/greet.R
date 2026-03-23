#!/usr/bin/env Rscript
# greet.R — Simple greeting script for the demo skill
#
# Usage: Rscript greet.R [name]
# Output: Hello, <name>!

args <- commandArgs(trailingOnly = TRUE)
name <- if (length(args) >= 1L) args[[1L]] else "World"

cat(sprintf("Hello, %s!\n", name))
