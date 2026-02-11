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

normalize_newlines = function(x) {
	x = gsub("\r\n", "\n", x, fixed = TRUE)
	x = gsub("\r", "\n", x, fixed = TRUE)
	x
}

# Generic normalization: strip trailing whitespace at end-of-line
normalize_eol_ws = function(x) {
	gsub("[ \t]+(?=\n)", "", x, perl = TRUE)
}

detect_crlf = function(x) {
	grepl("\r\n", x, fixed = TRUE)
}

write_all = function(path, txt, use_crlf) {
	if (use_crlf) {
		txt = gsub("\n", "\r\n", txt, fixed = TRUE)
	}
	con = file(path, open = "wb")
	on.exit(close(con), add = TRUE)
	writeBin(charToRaw(txt), con)
}

txt0 = read_all(fn)
from0 = read_all(from_fn)
to0 = read_all(to_fn)

use_crlf = detect_crlf(txt0)

txt = normalize_eol_ws(normalize_newlines(txt0))
from = normalize_eol_ws(normalize_newlines(from0))
to = normalize_newlines(to0)

pos = regexpr(from, txt, fixed = TRUE)[[1]]
if (pos == -1) {
	stop(sprintf("Target block not found in '%s' (from_file='%s')", fn, from_fn))
}

txt_new = sub(from, to, txt, fixed = TRUE)
write_all(fn, txt_new, use_crlf)

message(sprintf("Replaced block in '%s'", fn))
