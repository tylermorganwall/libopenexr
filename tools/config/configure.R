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
DEFLATE_LIB_ARCH = normalizePath(
	sprintf(
		"%s/%s",
		system.file(
			"lib",
			package = "libdeflate",
			mustWork = TRUE
		),
		Sys.info()[["machine"]]
	),
	winslash = "/"
)

# Use pkg-config (if available) to find a system library
package_name = "libopenexr"
static_library_name = "libOpenEXR-3_4"

package_version = "3.4.0"
lib_system = ""

pkgconfig_path = Sys.which("pkg-config")

lib_exists = FALSE
LIB_INCLUDE_ASSIGN = ""
LIB_LINK_ASSIGN = ""

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

		lib_include = quote_paths(
			system2(
				pkgconfig_path,
				c("--cflags", package_name),
				stdout = TRUE
			),
			prefix = "-I"
		)

		message(
			sprintf("*** configure: using include path '%s'", lib_include)
		)

		lib_link = quote_paths(
			system2(
				pkgconfig_path,
				c("--libs-only-L", package_name),
				stdout = TRUE
			),
			prefix = "-L"
		)

		message(
			sprintf(
				"*** configure: using link path '%s'",
				lib_link
			)
		)
		if (nzchar(lib_include)) {
			LIB_INCLUDE_ASSIGN = sprintf('LIB_INCLUDE = %s', lib_include) #This should already have -I
		}
		if (nzchar(lib_link)) {
			LIB_LINK_ASSIGN = sprintf('LIB_LINK = %s', lib_link) #This should already have -L
		}
	} else {
		message(sprintf("*** %s not found by pkg-config", package_name))
	}
} else {
	message("*** pkg-config not available, skipping to common locations")
}

if (!lib_exists) {
	fallback_prefixes = c(
		"/opt/R/arm64",
		"/opt/R/x86_64",
		"/opt/homebrew",
		"/usr/local",
		"/usr"
	)

	for (prefix in fallback_prefixes) {
		lib_exists_check = file.exists(file.path(
			prefix,
			"lib",
			sprintf("%s.a", static_library_name)
		))
		header_exists = dir.exists(file.path(prefix, "include", "OpenEXR"))

		if (lib_exists_check && header_exists) {
			lib_exists = TRUE
			lib_link = file.path(
				prefix,
				"lib"
			)
			lib_include = file.path(
				prefix,
				"include"
			)
			if (nzchar(lib_include)) {
				LIB_INCLUDE_ASSIGN = sprintf(
					'LIB_INCLUDE = -I"%s"',
					lib_include
				) #This doesn't have -I yet
			}
			if (nzchar(lib_link)) {
				LIB_LINK_ASSIGN = sprintf('LIB_LINK = -L"%s"', lib_link) #This doesn't have -L yet
			}
			break
		}
	}
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
#Now find dependencies

define(
	PACKAGE_BASE_DIR = PACKAGE_BASE_DIR,
	TARGET_ARCH = TARGET_ARCH,
	CMAKE = CMAKE,
	LIB_EXISTS = as.character(lib_exists),
	IMATH_INCLUDE_DIR = IMATH_INCLUDE_DIR,
	IMATH_LIB_ARCH = IMATH_LIB_ARCH,
	LIB_LINK_ASSIGN = LIB_LINK_ASSIGN,
	LIB_INCLUDE_ASSIGN = LIB_INCLUDE_ASSIGN,
	DEFLATE_LIB_ARCH = DEFLATE_LIB_ARCH
)

if (!dir.exists("src/OpenEXR/build")) {
	dir.create("src/OpenEXR/build")
}

file_cache = "src/OpenEXR/build/initial-cache.cmake"
writeLines(
	sprintf(
		r"-{set(CMAKE_C_FLAGS "-fPIC -fvisibility=hidden" CACHE STRING "C flags")
set(CMAKE_CXX_FLAGS "-fPIC -fvisibility=hidden -fvisibility-inlines-hidden" CACHE STRING "C++ flags")
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Position independent code")
set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build shared libs")
set(CMAKE_OSX_ARCHITECTURES "%s" CACHE STRING "Target architecture")}-",
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
if (status != 0) {
	stop("CMake configure step failed")
}

setwd(PACKAGE_BASE_DIR)

configure_file("src/Makevars.in")
configure_file("src/Makevars.win.in")
