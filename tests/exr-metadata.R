library(libopenexr)

r = matrix(seq(0.1, 0.8, length.out = 8), nrow = 2, ncol = 4)
g = r + 0.1
b = r + 0.2
a = matrix(1, nrow = 2, ncol = 4)
metadata = list(
  chromaticities = list(
    red = c(0.64, 0.33),
    green = c(0.30, 0.60),
    blue = c(0.15, 0.06),
    white = c(0.3127, 0.3290)
  ),
  adoptedNeutral = c(0.3127, 0.3290),
  whiteLuminance = 80,
  envmap = "latlong"
)

tmpfile = tempfile(fileext = ".exr")
write_exr(tmpfile, r, g, b, a, metadata = metadata)

expect_numeric_equal = function(actual, expected) {
  stopifnot(isTRUE(all.equal(
    unname(actual),
    unname(expected),
    tolerance = 1e-6
  )))
}

exr = read_exr(tmpfile)
expect_numeric_equal(
  exr$metadata$chromaticities$red,
  metadata$chromaticities$red
)
expect_numeric_equal(
  exr$metadata$chromaticities$green,
  metadata$chromaticities$green
)
expect_numeric_equal(
  exr$metadata$chromaticities$blue,
  metadata$chromaticities$blue
)
expect_numeric_equal(
  exr$metadata$chromaticities$white,
  metadata$chromaticities$white
)
expect_numeric_equal(
  exr$metadata$adoptedNeutral,
  metadata$adoptedNeutral
)
expect_numeric_equal(
  exr$metadata$whiteLuminance,
  metadata$whiteLuminance
)
stopifnot(identical(exr$metadata$envmap, "latlong"))

exr_array = read_exr(tmpfile, array = TRUE)
stopifnot(identical(attr(exr_array, "metadata")$envmap, "latlong"))
