# Prepare your package for installation here.
# Use 'define()' to define configuration variables.
# Use 'configure_file()' to substitute configuration values.

# Common: Find C/C++ compilers, deal with ccache, find the architecture
# and find CMake.
is_windows = identical(.Platform$OS.type, "windows")
is_macos = identical(Sys.info()[['sysname']], "Darwin")

TARGET_ARCH = Sys.info()[["machine"]]
PACKAGE_BASE_DIR = normalizePath(getwd(), winslash = "/")

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
IMATH_LIB_ARCH = normalizePath(
  sprintf(
    "%s/%s",
    system.file(
      "lib",
      package = "libimath",
      mustWork = TRUE
    ),
    Sys.info()[["machine"]]
  ),
  winslash = "/"
)
# Use pkg-config (if available) to find a system library
package_name = "libopenexr"
openexr_version_header = file.path(
  PACKAGE_BASE_DIR,
  "src",
  "OpenEXR",
  "src",
  "lib",
  "OpenEXRCore",
  "openexr_version.h"
)
openexr_version_lines = readLines(openexr_version_header, warn = FALSE)
parse_openexr_version = function(field) {
  as.integer(sub(
    ".*\\s([0-9]+)\\s*$",
    "\\1",
    grep(
      sprintf("OPENEXR_VERSION_%s", field),
      openexr_version_lines,
      value = TRUE
    )[1]
  ))
}
openexr_version_major = parse_openexr_version("MAJOR")
openexr_version_minor = parse_openexr_version("MINOR")
openexr_version_patch = parse_openexr_version("PATCH")
openexr_api = sprintf("%s_%s", openexr_version_major, openexr_version_minor)
openexr_has_openjph = openexr_version_major >= 4
inst_arch_lib_dir = file.path(PACKAGE_BASE_DIR, "inst", "lib", TARGET_ARCH)
static_library_name = sprintf("libOpenEXR-%s", openexr_api)
static_lib_filename = sprintf("%s.a", static_library_name)
openjph_static_lib = if (openexr_has_openjph) {
  normalizePath(
    file.path(
      inst_arch_lib_dir,
      "libopenjph.a"
    ),
    winslash = "/",
    mustWork = FALSE
  )
} else {
  ""
}

package_version = sprintf(
  "%s.%s.%s",
  openexr_version_major,
  openexr_version_minor,
  openexr_version_patch
)
openjph_link_flags = if (openexr_has_openjph) openjph_static_lib else ""
lib_system = ""

read_runtime_link_flags = function(path) {
  if (!file.exists(path)) {
    return("")
  }

  flags = unlist(strsplit(
    trimws(paste(readLines(path, warn = FALSE), collapse = " ")),
    "\\s+"
  ))
  paste(unique(flags[nzchar(flags)]), collapse = " ")
}

runtime_link_flags = read_runtime_link_flags(
  file.path(IMATH_LIB_ARCH, "libimath-runtime-link-flags")
)
if (nzchar(runtime_link_flags)) {
  message(sprintf(
    "*** configure: using Imath runtime link flags '%s'",
    runtime_link_flags
  ))
} else {
  message(
    "*** configure: no Imath runtime link flags file found; using none"
  )
}

pkgconfig_path = Sys.which("pkg-config")

lib_exists = FALSE
LIB_INCLUDE_ASSIGN = ""
LIB_LINK_ASSIGN = ""
lib_link = ""

if (nzchar(pkgconfig_path)) {
  pc_status = system2(
    pkgconfig_path,
    c("--exists", sprintf("'%s >= %s'", package_name, package_version)),
    stdout = FALSE,
    stderr = FALSE
  )

  lib_exists = pc_status == 0

  if (lib_exists) {
    message(
      sprintf(
        "*** configure: system %s exists, using that for building the library",
        static_library_name
      )
    )
    quote_paths = function(pkgconfig_output, prefix = "-I") {
      include_dirs = strsplit(
        trimws(gsub(prefix, "", pkgconfig_output, fixed = TRUE)),
        "\\s+"
      )[[1]]

      if (length(include_dirs) == 0) {
        return("")
      }
      if (length(include_dirs) == 1 && include_dirs == "") {
        return("")
      }

      return(
        paste(
          paste0(
            prefix,
            vapply(
              include_dirs,
              shQuote,
              "character"
            )
          ),
          collapse = " "
        )
      )
    }
    check_existence = function(lib_link_output, static_lib_filename) {
      any(file.exists(file.path(
        gsub(
          pattern = "(-L)|('|\")",
          "",
          x = unlist(strsplit(
            lib_link_output,
            split = " "
          ))
        ),
        static_lib_filename
      )))
    }

    lib_include = quote_paths(
      system2(
        pkgconfig_path,
        c("--cflags", package_name),
        stdout = TRUE
      ),
      prefix = "-I"
    )

    lib_link = quote_paths(
      system2(
        pkgconfig_path,
        c("--libs-only-L", package_name),
        stdout = TRUE
      ),
      prefix = "-L"
    )

    if (!check_existence(lib_link, static_lib_filename)) {
      lib_exists = FALSE
    } else {
      if (nzchar(lib_include)) {
        message(
          sprintf(
            "*** configure: using include path '%s'",
            lib_include
          )
        )
        LIB_INCLUDE_ASSIGN = sprintf('LIB_INCLUDE = %s', lib_include) #This should already have -I
      } else {
        lib_exists = FALSE
      }
      if (nzchar(lib_link)) {
        message(
          sprintf(
            "*** configure: using link path '%s'",
            lib_link
          )
        )
        LIB_LINK_ASSIGN = sprintf('LIB_LINK = %s', lib_link) #This should already have -L
      } else {
        message(sprintf(
          "*** %s found by pkg-config, but returned no link directory--skipping",
          package_name
        ))
        lib_exists = FALSE
      }
    }
  } else {
    message(sprintf("*** %s not found by pkg-config", package_name))
  }
} else {
  message("*** pkg-config not available, building bundled version")
}

syswhich_cmake = Sys.which("cmake")

if (syswhich_cmake != "") {
  CMAKE = normalizePath(syswhich_cmake, winslash = "/")
} else {
  if (is_macos) {
    cmake_found_in_app_folder = file.exists(
      "/Applications/CMake.app/Contents/bin/cmake"
    )
    if (cmake_found_in_app_folder) {
      CMAKE = normalizePath("/Applications/CMake.app/Contents/bin/cmake")
    } else {
      stop("CMake not found during configuration.")
    }
  } else {
    stop("CMake not found during configuration.")
  }
}
# Configure makevars

define(
  PACKAGE_BASE_DIR = PACKAGE_BASE_DIR,
  TARGET_ARCH = TARGET_ARCH,
  CMAKE = CMAKE,
  OPENEXR_API = openexr_api,
  OPENJPH_LINK_FLAGS = openjph_link_flags,
  OPENJPH_STATIC_LIB = openjph_static_lib,
  RUNTIME_LINK_FLAGS = runtime_link_flags,
  LIB_EXISTS = as.character(lib_exists),
  IMATH_INCLUDE_DIR = IMATH_INCLUDE_DIR,
  IMATH_LIB_ARCH = IMATH_LIB_ARCH,
  LIB_LINK_ASSIGN = LIB_LINK_ASSIGN,
  LIB_INCLUDE_ASSIGN = LIB_INCLUDE_ASSIGN
)


#Create build dir and
build_dir = file.path(PACKAGE_BASE_DIR, "src/OpenEXR/build-cran")
if (dir.exists(build_dir)) {
  unlink(build_dir, recursive = TRUE, force = TRUE)
}
dir.create(build_dir, recursive = TRUE, showWarnings = FALSE)

cache_dir = file.path(PACKAGE_BASE_DIR, "src/OpenEXR/build")
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

file_cache = file.path(cache_dir, "initial-cache.cmake")

cache_lines = c(
  'set(CMAKE_C_FLAGS "-fPIC -fvisibility=hidden" CACHE STRING "C flags")',
  'set(CMAKE_CXX_FLAGS "-fPIC -fvisibility=hidden -fvisibility-inlines-hidden" CACHE STRING "C++ flags")',
  'set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Position independent code")',
  'set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type")',
  'set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libs")'
)
if (is_macos) {
  cache_lines = c(
    cache_lines,
    sprintf(
      'set(CMAKE_OSX_ARCHITECTURES "%s" CACHE STRING "Target architecture")',
      TARGET_ARCH
    )
  )
}
writeLines(cache_lines, file_cache)

inst_dir = file.path(PACKAGE_BASE_DIR, "inst")
dir.create(inst_dir, recursive = TRUE, showWarnings = FALSE)

src_dir = ".." # evaluated inside build-cran/

cmake_cfg = c(
  src_dir,
  "-C",
  file_cache,
  paste0("-DCMAKE_INSTALL_PREFIX=", inst_dir),
  paste0("-DCMAKE_INSTALL_LIBDIR=lib/", TARGET_ARCH),
  paste0("-DImath_DIR=", file.path(IMATH_LIB_ARCH, "cmake", "Imath")),
  "-DCMAKE_CXX_STANDARD=17",
  "-DOPENEXR_INSTALL_PKG_CONFIG=ON",
  "-DBUILD_SHARED_LIBS=OFF",
  "-DOPENEXR_BUILD_TOOLS=OFF",
  "-DOPENEXR_BUILD_EXAMPLES=OFF",
  "-DOPENEXR_IS_SUBPROJECT=ON",
  "-DCMAKE_BUILD_TYPE=Release",
  "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
  "-DOPENEXR_FORCE_INTERNAL_OPENJPH=ON"
)

message(
  "Forcing vendored OpenEXR libdeflate (OPENEXR_FORCE_INTERNAL_DEFLATE=ON)"
)
cmake_cfg = c(cmake_cfg, "-DOPENEXR_FORCE_INTERNAL_DEFLATE=ON")

if (openexr_has_openjph) {
  # Keep OpenJPH in the vendored install prefix so final package linking
  # does not depend on a system-level openjph path.
  cmake_cfg = c(cmake_cfg, "-DOPENEXR_FORCE_INTERNAL_OPENJPH=ON")
}


read_config_value = function(key) {
  value = r_cmd_config(key)
  if (is.null(value)) {
    return("")
  }
  trimws(paste(value, collapse = " "))
}

first_non_empty = function(values) {
  values = trimws(values)
  values = values[nzchar(values)]
  if (length(values) == 0) {
    return("")
  }
  values[[1]]
}

extract_compiler_flags = function(cmd) {
  tokens = strsplit(trimws(cmd), "\\s+")[[1]]
  if (length(tokens) <= 1) {
    return("")
  }
  compiler_tokens = 1
  compiler_wrappers = c("ccache", "sccache", "distcc")
  if (
    basename(tokens[[1]]) %in%
      compiler_wrappers &&
      length(tokens) > compiler_tokens
  ) {
    compiler_tokens = compiler_tokens + 1
  }
  paste(tokens[-seq_len(compiler_tokens)], collapse = " ")
}

has_standard_flag = function(flags) {
  grepl("(^|[[:space:]])-std([=[:space:]]|$)", flags)
}

cc_cmd = first_non_empty(c(
  Sys.getenv("CC", unset = ""),
  read_config_value("CC")
))

cxx_cmd = first_non_empty(c(
  Sys.getenv("CXX", unset = ""),
  read_config_value("CXX")
))

cxx_flags = extract_compiler_flags(cxx_cmd)
cxx_std_flag = first_non_empty(c(
  Sys.getenv("CXX17STD", unset = ""),
  read_config_value("CXX17STD")
))
if (!has_standard_flag(cxx_flags) && nzchar(cxx_std_flag)) {
  message(sprintf(
    "*** configure: adding C++ standard flag '%s'",
    cxx_std_flag
  ))
  cxx_flags = paste(
    c(cxx_flags, cxx_std_flag)[
      nzchar(c(cxx_flags, cxx_std_flag))
    ],
    collapse = " "
  )
}

define(
  MAKE_CXX_FLAGS = cxx_flags
)

cmake_env = character()
if (nzchar(cc_cmd)) {
  cmake_env["CC"] = cc_cmd
  message(sprintf("*** configure: CMake CC='%s'", cc_cmd))
}
if (nzchar(cxx_cmd)) {
  cmake_env["CXX"] = cxx_cmd
  message(sprintf("*** configure: CMake CXX='%s'", cxx_cmd))
}

oldwd = getwd()
setwd(build_dir)
on.exit(setwd(oldwd), add = TRUE)

status = with_envvar(cmake_env, system2(CMAKE, cmake_cfg))
if (status != 0) {
  stop("CMake configure step failed")
}

setwd(oldwd)
configure_file("src/Makevars.in")
configure_file("src/Makevars.win.in")
