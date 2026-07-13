#!/usr/bin/env bash
#
# mayhem/build.sh — build pdfalto (PDF -> ALTO XML converter, xpdf-based).
#
# Builds TWO trees:
#   build/       sanitized (ASan+UBSan, halting) + DWARF-3 — the fuzz target
#                (/mayhem/build/pdfalto, a file-input CLI: pdfalto <pdf> <xml>)
#   build-test/  the project's NORMAL flags — the functional-oracle binary that
#                mayhem/test.sh runs (never compiled by test.sh)
#
# Third-party static libs (libxml2, libpng, zlib, freetype, ICU) are pre-built
# and committed under libs/ by upstream; the xpdf-4.05 submodule is compiled
# from source, so the PDF-parsing code under fuzz IS instrumented.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS COVERAGE_FLAGS

# Two UBSan checks are relaxed for the fuzz build (ASan + all other UBSan checks
# stay ON and halting):
#   vptr — xpdf's PDFDoc ctor takes a PDFCore* and the viewer classes PDFCore/
#          DisplayState ARE compiled into libxpdf.a, but their dependencies
#          (TileMap/TileCache/TileCompositor/TextOutputDev) are commented out of
#          xpdf-4.05's CMakeLists. -fsanitize=vptr emits RTTI references that force
#          the linker to pull PDFCore.cc.o → undefined-reference link failure.
#          Disabling only vptr lets those unused viewer objects stay unreferenced.
#   enum — xpdf reads several tri-state enum fields (e.g. CryptAlgorithm in
#          XRef.cc) before they are set, so -fsanitize=enum aborts on ~every PDF
#          (a benign invalid-enum-load flood that would drown real defects).
SAN_RELAX="-fno-sanitize=vptr,enum"

cd "$SRC"

# CI's build context (actions/checkout + docker build context .) carries the
# xpdf-4.05 submodule only as a gitlink — fetch its contents here so the build
# is self-sufficient. No-op when the submodule is already populated.
if [ -d .git ] && [ ! -e xpdf-4.05/CMakeLists.txt ]; then
  git submodule update --init --recursive
fi

# xpdf generates aconf.h into <cmake-binary>/xpdf-4.05 (configure_file in
# xpdf-4.05/cmake-config.txt), but upstream's CMakeLists points the include dir
# at xpdf-4.05/build — a stale path with an out-of-tree build. Rather than edit
# the upstream CMakeLists (keep the port additive), point the compiler at the
# real generated-header dir via -I. It exists by the time compilation runs.

# 1) Sanitized fuzz build: project + xpdf submodule compiled with ASan+UBSan and DWARF-3.
# The extra linked object bakes in ASan defaults (detect_leaks=0 — see
# mayhem/asan_default_options.c) so no runtime ASAN_OPTIONS is needed.
mkdir -p build
"$CC" -c mayhem/asan_default_options.c -o build/asan_default_options.o
cmake -B build \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $SAN_RELAX $DEBUG_FLAGS -I$SRC/build/xpdf-4.05" \
      -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $SAN_RELAX $DEBUG_FLAGS -I$SRC/build/xpdf-4.05" \
      -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG" \
      -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG" \
      -DCMAKE_EXE_LINKER_FLAGS="$SRC/build/asan_default_options.o"
cmake --build build -j"$MAYHEM_JOBS"

# 2) Oracle build with the project's normal flags (independent tree; test.sh only RUNS it).
cmake -B build-test \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS -I$SRC/build-test/xpdf-4.05" \
      -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS -I$SRC/build-test/xpdf-4.05"
cmake --build build-test -j"$MAYHEM_JOBS"
