#!/usr/bin/env Rscript
args = commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
	stop("Usage: replace-block.R <file> <from_file> <to_file>")
}

fn = args[[1]]
from_fn = args[[2]]
to_fn = args[[3]]

read_all = function(path) {
	raw = readBin(path, what = "raw", n = file.info(path)$size)
	rawToChar(raw)
}

txt = read_all(fn)
from = read_all(from_fn)
to = read_all(to_fn)

pos = regexpr(from, txt, fixed = TRUE)[[1]]
if (pos == -1) {
	stop(sprintf("Target block not found in '%s' (from_file='%s')", fn, from_fn))
}

txt_new = sub(from, to, txt, fixed = TRUE)

message("----Patching----\n", from, "\n----to----\n", to)

newline = if (.Platform$OS.type == "windows") "\r\n" else "\n"
txt_new = gsub("\r\n|\r|\n", newline, txt_new)

con = file(fn, open = "wb")
on.exit(close(con), add = TRUE)
writeBin(charToRaw(txt_new), con)
