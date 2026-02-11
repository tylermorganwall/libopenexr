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

detect_crlf = function(x) {
	grepl("\r\n", x, fixed = TRUE)
}

txt0 = read_all(fn)
from0 = read_all(from_fn)
to0 = read_all(to_fn)

# Preserve the newline style of the file being patched
use_crlf = detect_crlf(txt0)

# Normalize for matching
txt = normalize_newlines(txt0)
from = normalize_newlines(from0)
to = normalize_newlines(to0)

pos = regexpr(from, txt, fixed = TRUE)[[1]]
if (pos == -1) {
	# Helpful debugging: show first mismatch context lengths without dumping entire blocks
	stop(sprintf(
		"Target block not found in '%s' (from_file='%s').\nLengths: txt=%d, from=%d\n",
		fn,
		from_fn,
		nchar(txt),
		nchar(from)
	))
}

txt_new = sub(from, to, txt, fixed = TRUE)

# Restore original newline convention
if (use_crlf) {
	txt_new = gsub("\n", "\r\n", txt_new, fixed = TRUE)
}

con = file(fn, open = "wb")
on.exit(close(con), add = TRUE)
writeBin(charToRaw(txt_new), con)

message(sprintf(
	"Replaced block in '%s' using '%s' -> '%s'",
	fn,
	from_fn,
	to_fn
))
