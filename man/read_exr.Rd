% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/read_write_exr.R
\name{read_exr}
\alias{read_exr}
\title{Read an OpenEXR image}
\usage{
read_exr(path, array = FALSE)
}
\arguments{
\item{path}{Character scalar. Path to an `.exr` file.}

\item{array}{Default `FALSE`. Return a 4-layer RGBA array instead of a list.}
}
\value{
A list with elements `r`, `g`, `b`, `a` (numeric matrices), and
  the integer dimensions `width`, `height`.
}
\description{
Load an RGBA OpenEXR image into R numeric matrices.
}
\examples{
#Write the included data to an EXR file
tmpfile = tempfile(fileext = ".exr")
write_exr(tmpfile,
          widecolorgamut[,,1],
          widecolorgamut[,,2],
          widecolorgamut[,,3],
          widecolorgamut[,,4])
exr_file = read_exr(tmpfile)
str(exr_file)
}
