#' Read an OpenEXR image
#'
#' Load an RGBA OpenEXR image into R numeric matrices.
#'
#' @param path Character scalar. Path to an `.exr` file.
#' @return A list with elements `r`, `g`, `b`, `a` (numeric matrices), and
#'   the integer dimensions `width`, `height`.
#' @export
read_exr = function(path) {
  stopifnot(is.character(path), length(path) == 1L)
  .Call("C_read_exr", path, PACKAGE = "libopenexr")
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
#' @return None.
#' @export
write_exr = function(
  path,
  r,
  g,
  b,
  a = matrix(1, nrow = nrow(r), ncol = ncol(r))
) {
  stopifnot(
    all(dim(r) == dim(g)) &&
      all(dim(r) == dim(b)) &&
      all(dim(r) == dim(a))
  )
  .Call(
    "C_write_exr",
    path,
    r,
    g,
    b,
    a,
    as.integer(ncol(r)),
    as.integer(nrow(r)),
    PACKAGE = "libopenexr"
  )
  invisible(NULL)
}
