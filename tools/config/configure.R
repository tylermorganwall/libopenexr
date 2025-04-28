# Prepare your package for installation here.
# Use 'define()' to define configuration variables.
# Use 'configure_file()' to substitute configuration values.

CC_FULL = normalizePath(Sys.which(strsplit(r_cmd_config("CC"), " ")[[1]][1]))
CXX_FULL = normalizePath(Sys.which(strsplit(r_cmd_config("CXX"), " ")[[1]][1]))
TARGET_ARCH = Sys.info()[["machine"]]
PACKAGE_BASE_DIR = normalizePath(getwd())
IMATH_LIB_DIR = system.file(
  "lib",
  package = "libimath",
  mustWork = TRUE
)
IMATH_INCLUDE_DIR = system.file(
  "include",
  "Imath",
  package = "libimath",
  mustWork = TRUE
)
IMATH_LIB_ARCH = normalizePath(sprintf(
  "%s/%s",
  system.file(
    "lib",
    package = "libimath",
    mustWork = TRUE
  ),
  Sys.info()[["machine"]]
))
DEFLATE_LIB_ARCH = normalizePath(sprintf(
  "%s/%s",
  system.file(
    "lib",
    package = "libdeflate",
    mustWork = TRUE
  ),
  Sys.info()[["machine"]]
))
CMAKE = normalizePath(Sys.which("cmake"))

define(
  PACKAGE_BASE_DIR = PACKAGE_BASE_DIR,
  TARGET_ARCH = TARGET_ARCH,
  IMATH_LIB_DIR = IMATH_LIB_DIR,
  IMATH_INCLUDE_DIR = IMATH_INCLUDE_DIR,
  CMAKE = CMAKE,
  IMATH_LIB_ARCH = IMATH_LIB_ARCH,
  CC_FULL = CC_FULL,
  CXX_FULL = CXX_FULL,
  DEFLATE_LIB_DIR = system.file(
    "lib",
    package = "libdeflate",
    mustWork = TRUE
  ),
  DEFLATE_LIB_ARCH = DEFLATE_LIB_ARCH
)

if (!dir.exists("src/OpenEXR/build")) {
  dir.create("src/OpenEXR/build")
}

file_cache = "src/OpenEXR/build/initial-cache.cmake"
writeLines(
  sprintf(
    r"-{set(CMAKE_C_COMPILER "%s" CACHE FILEPATH "C compiler")
set(CMAKE_CXX_COMPILER "%s" CACHE FILEPATH "C++ compiler")
set(CMAKE_C_FLAGS "-fPIC -fvisibility=hidden" CACHE STRING "C flags")
set(CMAKE_CXX_FLAGS "-fPIC -fvisibility=hidden -fvisibility-inlines-hidden" CACHE STRING "C++ flags")
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Position independent code")
set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libs")
set(CMAKE_OSX_ARCHITECTURES "%s" CACHE STRING "Target architecture")}-",
    CC_FULL,
    CXX_FULL,
    TARGET_ARCH
  ),
  file_cache
)


inst_dir <- file.path(PACKAGE_BASE_DIR, "inst") # ${PACKAGE_BASE_DIR}/inst
dir.create(inst_dir, recursive = TRUE, showWarnings = FALSE)

build_dir <- file.path(PACKAGE_BASE_DIR, "src/OpenEXR/build") # already created earlier
src_dir <- ".." # evaluated inside build/

cmake_cfg <- c(
  src_dir,
  "-C",
  "../build/initial-cache.cmake",
  paste0("-DCMAKE_INSTALL_PREFIX=", inst_dir),
  paste0("-DCMAKE_INSTALL_LIBDIR=lib/", TARGET_ARCH),
  paste0("-DImath_DIR=", file.path(IMATH_LIB_ARCH, "cmake", "Imath")),
  paste0(
    "-Dlibdeflate_DIR=",
    file.path(DEFLATE_LIB_ARCH, "cmake", "libdeflate")
  ),
  "-DOPENEXR_INSTALL_PKG_CONFIG=ON",
  "-DBUILD_SHARED_LIBS=OFF",
  "-DBUILD_SHARED_LIBS=OFF",
  "-DOPENEXR_BUILD_TOOLS=OFF",
  "-DOPENEXR_BUILD_EXAMPLES=OFF",
  "-DOPENEXR_IS_SUBPROJECT=ON",
  "-DCMAKE_BUILD_TYPE=Release",
  "-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
)

setwd(build_dir)

status <- system2(CMAKE, cmake_cfg)
if (status != 0) stop("CMake configure step failed")

setwd(PACKAGE_BASE_DIR)

configure_file("src/Makevars.in")
configure_file("src/Makevars.win.in")
