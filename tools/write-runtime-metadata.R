args = commandArgs(trailingOnly = TRUE)
if (length(args) < 2 || length(args) > 3) {
  stop(
    "usage: write-runtime-metadata.R <library-directory> <openexr-api> [runtime-flags]"
  )
}

lib_dir = normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
openexr_api = args[[2]]
transitive_flags = if (length(args) >= 3) args[[3]] else ""

metadata_file = file.path(lib_dir, "libopenexr-runtime-link-flags")

split_flags = function(x) {
  flags = unlist(strsplit(trimws(paste(x, collapse = " ")), "\\s+"))
  unique(flags[nzchar(flags)])
}

read_symbols = function(path) {
  if (!file.exists(path)) {
    return(character())
  }

  nm = Sys.which("nm")
  if (!nzchar(nm)) {
    return(character())
  }

  tryCatch(
    system2(nm, c("-g", path), stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )
}

has_symbol = function(symbols, pattern) {
  any(grepl(pattern, symbols, fixed = TRUE))
}

append_unique = function(x, value) {
  unique(c(x, value))
}

is_windows = identical(.Platform$OS.type, "windows")
is_macos = identical(Sys.info()[["sysname"]], "Darwin")

archive_names = c(
  sprintf("libIex-%s.a", openexr_api),
  sprintf("libIlmThread-%s.a", openexr_api),
  sprintf("libOpenEXRCore-%s.a", openexr_api),
  sprintf("libOpenEXR-%s.a", openexr_api),
  sprintf("libOpenEXRUtil-%s.a", openexr_api),
  "libopenjph.a"
)
archives = file.path(lib_dir, archive_names)
archives = archives[file.exists(archives)]
symbols = unlist(lapply(archives, read_symbols), use.names = FALSE)

runtime_flags = split_flags(transitive_flags)
if (!is_windows && !is_macos && has_symbol(symbols, "_ZNSt3__1")) {
  runtime_flags = append_unique(runtime_flags, "-lc++")
}
if (!is_windows && has_symbol(symbols, "__ubsan_handle")) {
  runtime_flags = append_unique(runtime_flags, "-fsanitize=undefined")
}
if (!is_windows && has_symbol(symbols, "__asan_")) {
  runtime_flags = append_unique(runtime_flags, "-fsanitize=address")
}
if (!is_windows && has_symbol(symbols, "__tsan_")) {
  runtime_flags = append_unique(runtime_flags, "-fsanitize=thread")
}

runtime_flags_text = paste(runtime_flags, collapse = " ")
invisible(writeLines(runtime_flags_text, metadata_file, useBytes = TRUE))

remove_marked_block = function(lines, begin, end) {
  start = grep(begin, lines, fixed = TRUE)
  stop = grep(end, lines, fixed = TRUE)

  if (length(start) == 0 || length(stop) == 0) {
    return(lines)
  }

  keep = rep(TRUE, length(lines))
  for (idx in seq_along(start)) {
    matching_stop = stop[stop >= start[[idx]]]
    if (length(matching_stop) > 0) {
      keep[start[[idx]]:matching_stop[[1]]] = FALSE
    }
  }
  lines[keep]
}

patch_pkg_config = function(path, flags) {
  if (!file.exists(path) || length(flags) == 0) {
    return(invisible(FALSE))
  }

  lines = readLines(path, warn = FALSE)
  private_idx = grep("^Libs\\.private:", lines)
  existing_flags = character()

  if (length(private_idx) > 0) {
    existing_flags = split_flags(sub(
      "^Libs\\.private:\\s*",
      "",
      lines[[private_idx[[1]]]]
    ))
  }

  merged_flags = paste(unique(c(existing_flags, flags)), collapse = " ")
  new_line = paste("Libs.private:", merged_flags)

  if (length(private_idx) > 0) {
    lines[[private_idx[[1]]]] = new_line
  } else {
    libs_idx = grep("^Libs:", lines)
    if (length(libs_idx) > 0) {
      lines = append(lines, new_line, after = libs_idx[[1]])
    } else {
      lines = c(lines, new_line)
    }
  }

  writeLines(lines, path, useBytes = TRUE)
  invisible(TRUE)
}

cmake_quote_list = function(values) {
  paste(values, collapse = ";")
}

patch_cmake_targets = function(path, targets, flags) {
  if (!file.exists(path)) {
    return(invisible(FALSE))
  }

  begin = "# libopenexr R package runtime link flags begin"
  end = "# libopenexr R package runtime link flags end"
  lines = remove_marked_block(readLines(path, warn = FALSE), begin, end)

  link_libraries = flags[grepl("^-l", flags)]
  link_options = setdiff(flags, link_libraries)

  if (length(link_libraries) > 0 || length(link_options) > 0) {
    block = c(begin)
    block = c(
      block,
      sprintf(
        "foreach(_libopenexr_target IN ITEMS %s)",
        paste(targets, collapse = " ")
      )
    )
    block = c(block, '  if(TARGET "${_libopenexr_target}")')
    if (length(link_libraries) > 0) {
      block = c(
        block,
        "    set_property(TARGET \"${_libopenexr_target}\" APPEND PROPERTY",
        sprintf(
          '      INTERFACE_LINK_LIBRARIES "%s"',
          cmake_quote_list(link_libraries)
        ),
        "    )"
      )
    }
    if (length(link_options) > 0) {
      block = c(
        block,
        "    set_property(TARGET \"${_libopenexr_target}\" APPEND PROPERTY",
        sprintf(
          '      INTERFACE_LINK_OPTIONS "%s"',
          cmake_quote_list(link_options)
        ),
        "    )"
      )
    }
    block = c(block, "  endif()", "endforeach()", end, "")

    insert_before = grep(
      "^# Load information for each installed configuration\\.",
      lines
    )
    if (length(insert_before) > 0) {
      lines = append(lines, block, after = insert_before[[1]] - 1)
    } else {
      lines = c(lines, "", block)
    }
  }

  writeLines(lines, path, useBytes = TRUE)
  invisible(TRUE)
}

pc_files = unique(unlist(lapply(
  c(file.path(lib_dir, "pkgconfig"), lib_dir),
  function(pc_dir) file.path(pc_dir, c("OpenEXR.pc", "OpenEXRUtil.pc"))
)))
invisible(lapply(pc_files, patch_pkg_config, flags = runtime_flags))

patch_cmake_targets(
  file.path(lib_dir, "cmake", "OpenEXR", "OpenEXRTargets.cmake"),
  c("OpenEXR::OpenEXR", "OpenEXR::OpenEXRUtil"),
  runtime_flags
)

if (nzchar(runtime_flags_text)) {
  message(sprintf(
    "Recorded OpenEXR runtime link flags: %s",
    runtime_flags_text
  ))
} else {
  message("No extra OpenEXR runtime link flags detected")
}
