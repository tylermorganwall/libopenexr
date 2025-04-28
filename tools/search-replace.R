#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
fn <- args[[1]]
stringval = args[[2]]
replace = args[[3]]
txt <- readLines(fn)
txt <- gsub(
  stringval,
  replace,
  txt
)
writeLines(txt, fn)
