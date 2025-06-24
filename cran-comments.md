## Fixes v3.4.0-2

This version fixes the issues with compiling on the CRAN 'blackswan' test environment, which resulted from failing to account for that build environment's use of aliases/symlinks to pass in the compiler cache tool 'ccache'. The prior version checked for 'ccache', but failed in the case where 'ccache' use was not explicit (as it called 'normalizePath()' after finding the compiler, which expanded the symlink):

$ ln -s $(which ccache) clang
$ ./clang -v
Apple clang version 15.0.0 (clang-1500.3.9.4)
$ Rscript -e 'normalizePath("./clang")'
[1] "/usr/local/Cellar/ccache/4.5.1/bin/ccache"

This version fixes that behavior.

(thanks to Ivan Krylov on r-package-devel for helping debug this issue)

## CHECK Results

This has been successfully checked on macOS --as-cran, all 30 rhub runners, win-builder (old/release/dev), and mac-builder (release/dev).