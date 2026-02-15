#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
path <- args[[1]]
stringval = args[[2]]
replace = args[[3]]
is_dir = dir.exists(path)
is_pragma_pattern = grepl(
	"^\\^\\(#\\\\s\\*pragma (warning|GCC diagnostic)",
	stringval,
	perl = TRUE
)

files = if (is_dir) {
	list.files(
		path,
		pattern = "\\.(c|cc|cpp|cxx|C|h|hh|hpp|hxx)$",
		recursive = TRUE,
		full.names = TRUE
	)
} else {
	path
}

changed_file_count = 0L
for (fn in files) {
	txt <- readLines(fn, warn = FALSE)
	if (replace == "__COMMENT_MATCHED_LINE__" || is_pragma_pattern) {
		matched = grepl(stringval, txt, perl = TRUE)
		txt_new = txt
		txt_new[matched] = ""
	} else {
		txt_new <- gsub(
			stringval,
			replace,
			txt,
			perl = TRUE
		)
	}
	if (any(txt_new == "/ /1")) {
		stop(sprintf(
			"Detected suspicious replacement '/ /1' in '%s' for pattern '%s'",
			fn,
			stringval
		))
	}
	newlines = txt_new != txt
	if (sum(newlines) > 0) {
		message(
			sprintf("Replaced the following lines in '%s':\n", fn),
			paste0(
				sprintf(" Old: '%s'\n New: '%s'", txt[newlines], txt_new[newlines]),
				collapse = "\n"
			)
		)
		changed_file_count = changed_file_count + 1L
		con = file(fn, open = "wb")
		writeLines(txt_new, con, sep = "\n", useBytes = TRUE)
		close(con)
	} else if (!is_dir) {
		message(
			sprintf("Did not find any changes to make in '%s'", fn)
		)
	}
}

if (is_dir) {
	message(sprintf("Updated %d file(s) under '%s'", changed_file_count, path))
}
