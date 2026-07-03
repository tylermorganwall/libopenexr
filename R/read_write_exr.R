#' Read an OpenEXR image
#'
#' Load an RGBA OpenEXR image into R numeric matrices.
#'
#' @param path Character scalar. Path to an `.exr` file.
#' @param array Default `FALSE`. Return a 4-layer RGBA array instead of a list.
#' @return A list with elements `r`, `g`, `b`, `a` (numeric matrices),
#'   the integer dimensions `width`, `height`, and a `metadata` list.
#'   If `array = TRUE`, the metadata list is returned as the `metadata`
#'   attribute.
#' @details The `metadata` list contains only metadata present in the file.
#'   `chromaticities` is returned as a named list of `red`, `green`, `blue`,
#'   and `white` xy vectors. `adoptedNeutral` is returned as an xy vector,
#'   `whiteLuminance` as a scalar, and `envmap` as `"latlong"` or `"cube"`.
#' @export
#' @examples
#' #Write the included data to an EXR file
#' tmpfile = tempfile(fileext = ".exr")
#' write_exr(tmpfile,
#'           widecolorgamut[,,1],
#'           widecolorgamut[,,2],
#'           widecolorgamut[,,3],
#'           widecolorgamut[,,4])
#' exr_file = read_exr(tmpfile)
#' str(exr_file)
read_exr = function(path, array = FALSE) {
  path = path.expand(path)
  stopifnot(is.character(path), length(path) == 1L)
  exr = .Call("C_read_exr", path, PACKAGE = "libopenexr")
  if (!array) {
    return(exr)
  } else {
    exr_arr = array(data = 0, dim = c(exr$width, exr$height, 4))
    exr_arr[,, 1] = exr$r
    exr_arr[,, 2] = exr$g
    exr_arr[,, 3] = exr$b
    exr_arr[,, 4] = exr$a
    attr(exr_arr, "metadata") = exr$metadata
    return(exr_arr)
  }
}

#' Write an OpenEXR image
#'
#' Save RGBA numeric matrices to an OpenEXR file (32‑bit float, ZIP compression).
#'
#' @param path Character scalar output file.
#' @param r Numeric matrix, red channel.
#' @param g Numeric matrix, green channel.
#' @param b Numeric matrix, blue channel.
#' @param a Numeric matrix, alpha channel.
#' @param metadata Default `NULL`. Optional EXR header metadata list with
#'   supported fields `chromaticities`, `adoptedNeutral`, `whiteLuminance`,
#'   and `envmap`.
#' @details `metadata$chromaticities` can be a named list with `red`, `green`,
#'   `blue`, and `white` numeric xy vectors, a 4x2 numeric matrix, or a numeric
#'   vector of length 8 in red, green, blue, white xy order. `adoptedNeutral`
#'   must be a length-2 numeric xy vector, `whiteLuminance` must be a numeric
#'   scalar, and `envmap` must be `"latlong"`, `"cube"`, `0`, or `1`.
#' @return None.
#' @export
#' @examples
#' #Write the included data to an EXR file
#' tmpfile = tempfile(fileext = ".exr")
#' write_exr(tmpfile,
#'           widecolorgamut[,,1],
#'           widecolorgamut[,,2],
#'           widecolorgamut[,,3],
#'           widecolorgamut[,,4])
write_exr = function(
  path,
  r,
  g,
  b,
  a = matrix(1, nrow = nrow(r), ncol = ncol(r)),
  metadata = NULL
) {
  path = path.expand(path)
  stopifnot(
    all(dim(r) == dim(g)) &&
      all(dim(r) == dim(b)) &&
      all(dim(r) == dim(a))
  )
  metadata = normalize_exr_metadata(metadata)
  .Call(
    "C_write_exr",
    path,
    r,
    g,
    b,
    a,
    as.integer(ncol(r)),
    as.integer(nrow(r)),
    metadata,
    PACKAGE = "libopenexr"
  )
  invisible(NULL)
}

#' Normalize EXR metadata
#'
#' @param metadata Default `NULL`. Optional EXR header metadata list.
#'
#' @keywords internal
#' @noRd
normalize_exr_metadata = function(metadata = NULL) {
  if (is.null(metadata)) {
    return(NULL)
  }
  if (!is.list(metadata)) {
    stop("`metadata` must be a list.", call. = FALSE)
  }
  metadata_names = names(metadata)
  if (
    is.null(metadata_names) ||
      any(!nzchar(metadata_names)) ||
      anyDuplicated(metadata_names)
  ) {
    stop("`metadata` must be a named list with unique names.", call. = FALSE)
  }
  supported = c("chromaticities", "adoptedNeutral", "whiteLuminance", "envmap")
  unknown = setdiff(metadata_names, supported)
  if (length(unknown) > 0) {
    stop(
      sprintf(
        "Unsupported EXR metadata field%s: %s.",
        if (length(unknown) == 1) "" else "s",
        paste(unknown, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  out = list()
  chromaticities = metadata[["chromaticities", exact = TRUE]]
  if (!is.null(chromaticities)) {
    out$chromaticities = normalize_exr_chromaticities(chromaticities)
  }
  adopted_neutral = metadata[["adoptedNeutral", exact = TRUE]]
  if (!is.null(adopted_neutral)) {
    out$adoptedNeutral = normalize_exr_numeric(
      adopted_neutral,
      2L,
      "metadata$adoptedNeutral"
    )
  }
  white_luminance = metadata[["whiteLuminance", exact = TRUE]]
  if (!is.null(white_luminance)) {
    out$whiteLuminance = normalize_exr_numeric(
      white_luminance,
      1L,
      "metadata$whiteLuminance"
    )
  }
  envmap = metadata[["envmap", exact = TRUE]]
  if (!is.null(envmap)) {
    out$envmap = normalize_exr_envmap(envmap)
  }
  out
}

#' Normalize EXR chromaticities
#'
#' @param chromaticities Chromaticities metadata.
#'
#' @keywords internal
#' @noRd
normalize_exr_chromaticities = function(chromaticities) {
  channels = c("red", "green", "blue", "white")
  if (is.list(chromaticities) && !is.data.frame(chromaticities)) {
    chromaticity_names = names(chromaticities)
    if (is.null(chromaticity_names)) {
      stop(
        "`metadata$chromaticities` must name red, green, blue, and white.",
        call. = FALSE
      )
    }
    missing = setdiff(channels, chromaticity_names)
    if (length(missing) > 0) {
      stop(
        sprintf(
          "`metadata$chromaticities` is missing: %s.",
          paste(missing, collapse = ", ")
        ),
        call. = FALSE
      )
    }
    chromaticities = unlist(chromaticities[channels], use.names = FALSE)
  } else if (is.matrix(chromaticities)) {
    if (
      !is.numeric(chromaticities) || !identical(dim(chromaticities), c(4L, 2L))
    ) {
      stop(
        "`metadata$chromaticities` must be a 4x2 numeric matrix.",
        call. = FALSE
      )
    }
    if (!is.null(rownames(chromaticities))) {
      missing = setdiff(channels, rownames(chromaticities))
      if (length(missing) > 0) {
        stop(
          sprintf(
            "`metadata$chromaticities` is missing row%s: %s.",
            if (length(missing) == 1) "" else "s",
            paste(missing, collapse = ", ")
          ),
          call. = FALSE
        )
      }
      chromaticities = chromaticities[channels, , drop = FALSE]
    }
    chromaticities = as.vector(t(chromaticities))
  }
  chromaticities = normalize_exr_numeric(
    chromaticities,
    8L,
    "metadata$chromaticities"
  )
  names(chromaticities) = paste(
    rep(channels, each = 2),
    rep(c("x", "y"), times = 4),
    sep = "."
  )
  chromaticities
}

#' Normalize EXR numeric metadata
#'
#' @param value Metadata value.
#' @param expected_length Expected length.
#' @param label Error label.
#'
#' @keywords internal
#' @noRd
normalize_exr_numeric = function(value, expected_length, label) {
  if (
    !is.numeric(value) ||
      length(value) != expected_length ||
      !all(is.finite(value))
  ) {
    stop(
      sprintf(
        "`%s` must be a finite numeric vector of length %d.",
        label,
        expected_length
      ),
      call. = FALSE
    )
  }
  as.numeric(value)
}

#' Normalize EXR envmap metadata
#'
#' @param envmap Envmap metadata.
#'
#' @keywords internal
#' @noRd
normalize_exr_envmap = function(envmap) {
  if (is.character(envmap) && length(envmap) == 1L && !is.na(envmap)) {
    value = tolower(envmap)
    value = gsub("[_-]", "", value)
    if (value %in% c("latlong", "latitudelongitude")) {
      return(0L)
    }
    if (value == "cube") {
      return(1L)
    }
  } else if (is.numeric(envmap) && length(envmap) == 1L && is.finite(envmap)) {
    if (envmap %in% c(0, 1)) {
      return(as.integer(envmap))
    }
  }
  stop(
    "`metadata$envmap` must be \"latlong\", \"cube\", 0, or 1.",
    call. = FALSE
  )
}
