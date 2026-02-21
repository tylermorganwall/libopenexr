#define R_NO_REMAP

#include <R.h>
#include <R_ext/Rdynload.h>
#include <Rinternals.h>

#include <ImathBox.h>
#include <ImfArray.h>
#include <ImfRgbaFile.h>

#include <ImfChannelList.h>
#include <ImfCompression.h>
#include <ImfFrameBuffer.h>
#include <ImfHeader.h>
#include <ImfInputFile.h>
#include <ImfOutputFile.h>
#include <vector>
#include <cmath>

using namespace OPENEXR_IMF_NAMESPACE;
using namespace IMATH_NAMESPACE;

// ---------------------------------------------------------------------
// helpers
inline void check_bool(bool ok, const char *msg) {
  if (!ok)
    Rf_error("%s", msg);
}

// ---------------------------------------------------------------------
// .Call("C_read_exr", "path/to/file.exr")

extern "C" SEXP C_read_exr(SEXP path_SEXP) {
  const char *path = CHAR(STRING_ELT(path_SEXP, 0));
  try {
    // Use a single worker thread for deterministic behavior across toolchains.
    InputFile file(path, 1);
    const Header &hdr = file.header();
    Box2i dw = hdr.dataWindow();
    const int w = dw.max.x - dw.min.x + 1;
    const int h = dw.max.y - dw.min.y + 1;

    // allocate float row-major buffers
    std::vector<float> r32(w*h), g32(w*h), b32(w*h), a32(w*h, 1.0f);

    FrameBuffer fb;
    const size_t xs = sizeof(float), ys = sizeof(float) * (size_t)w;

    // map (dw.min.x, dw.min.y) to r32[0]
    char *baseR = (char*)r32.data() - (dw.min.x*xs + dw.min.y*ys);
    char *baseG = (char*)g32.data() - (dw.min.x*xs + dw.min.y*ys);
    char *baseB = (char*)b32.data() - (dw.min.x*xs + dw.min.y*ys);
    char *baseA = (char*)a32.data() - (dw.min.x*xs + dw.min.y*ys);

    // If channel missing, you can skip inserting; here we assume R,G,B exist
    fb.insert("R", Slice(FLOAT, baseR, xs, ys));
    fb.insert("G", Slice(FLOAT, baseG, xs, ys));
    fb.insert("B", Slice(FLOAT, baseB, xs, ys));
    if (hdr.channels().findChannel("A")) // optional alpha
      fb.insert("A", Slice(FLOAT, baseA, xs, ys));

    file.setFrameBuffer(fb);
    file.readPixels(dw.min.y, dw.max.y);

    // Convert row-major float -> column-major double matrices for R
    SEXP rMat = PROTECT(Rf_allocMatrix(REALSXP, h, w));
    SEXP gMat = PROTECT(Rf_allocMatrix(REALSXP, h, w));
    SEXP bMat = PROTECT(Rf_allocMatrix(REALSXP, h, w));
    SEXP aMat = PROTECT(Rf_allocMatrix(REALSXP, h, w));
    double *r = REAL(rMat), *g = REAL(gMat), *b = REAL(bMat), *a = REAL(aMat);

    for (int y = 0; y < h; ++y)
      for (int x = 0; x < w; ++x) {
        const ptrdiff_t pos_col = x * (ptrdiff_t)h + y;
        const ptrdiff_t pos_row = y * (ptrdiff_t)w + x;
        r[pos_col] = r32[pos_row];
        g[pos_col] = g32[pos_row];
        b[pos_col] = b32[pos_row];
        a[pos_col] = a32[pos_row];
      }

    SEXP out = PROTECT(Rf_allocVector(VECSXP, 6));
    SET_VECTOR_ELT(out, 0, rMat);
    SET_VECTOR_ELT(out, 1, gMat);
    SET_VECTOR_ELT(out, 2, bMat);
    SET_VECTOR_ELT(out, 3, aMat);
    SET_VECTOR_ELT(out, 4, Rf_ScalarInteger(w));
    SET_VECTOR_ELT(out, 5, Rf_ScalarInteger(h));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 6));
    const char *nms[6] = {"r","g","b","a","width","height"};
    for (int i=0;i<6;++i) SET_STRING_ELT(names, i, Rf_mkChar(nms[i]));
    Rf_setAttrib(out, R_NamesSymbol, names);

    UNPROTECT(6);
    return out;
  } catch (const std::exception &e) {
    Rf_error("OpenEXR read error: %s", e.what());
  }
}

// ---------------------------------------------------------------------
// .Call("C_write_exr", path, r, g, b, a, width, height)
extern "C" SEXP C_write_exr(SEXP path_SEXP, SEXP rMat, SEXP gMat, SEXP bMat,
                            SEXP aMat, SEXP w_SEXP, SEXP h_SEXP) {
  const char *path = CHAR(STRING_ELT(path_SEXP, 0));
  const int w = INTEGER(w_SEXP)[0];
  const int h = INTEGER(h_SEXP)[0];

  check_bool(Rf_isMatrix(rMat) && Rf_isMatrix(gMat) && Rf_isMatrix(bMat) && Rf_isMatrix(aMat),
             "All channels must be matrices");
  check_bool(
      Rf_nrows(rMat) == h && Rf_ncols(rMat) == w &&
      Rf_nrows(gMat) == h && Rf_ncols(gMat) == w &&
      Rf_nrows(bMat) == h && Rf_ncols(bMat) == w &&
      Rf_nrows(aMat) == h && Rf_ncols(aMat) == w,
      "Dimension mismatch");

  SEXP rNum = PROTECT(Rf_coerceVector(rMat, REALSXP));
  SEXP gNum = PROTECT(Rf_coerceVector(gMat, REALSXP));
  SEXP bNum = PROTECT(Rf_coerceVector(bMat, REALSXP));
  SEXP aNum = PROTECT(Rf_coerceVector(aMat, REALSXP));

  const double *rD = REAL(rNum), *gD = REAL(gNum), *bD = REAL(bNum), *aD = REAL(aNum);

  // Pack into row-major float buffers (EXR expects x to stride fastest)
  std::vector<float> r32(w * h), g32(w * h), b32(w * h), a32(w * h);
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const ptrdiff_t pos_colmajor = x * (ptrdiff_t)h + y;   // R column-major
      const ptrdiff_t pos_rowmajor = y * (ptrdiff_t)w + x;   // EXR row-major
      auto ffin = [](double v) -> float {
        return std::isfinite(v) ? static_cast<float>(v) : 0.0f;
      };
      r32[pos_rowmajor] = ffin(rD[pos_colmajor]);
      g32[pos_rowmajor] = ffin(gD[pos_colmajor]);
      b32[pos_rowmajor] = ffin(bD[pos_colmajor]);
      a32[pos_rowmajor] = ffin(aD[pos_colmajor]);
    }
  }

  try {
    Header header(w, h); // dataWindow [0..w-1],[0..h-1]
    header.channels().insert("R", Channel(FLOAT));
    header.channels().insert("G", Channel(FLOAT));
    header.channels().insert("B", Channel(FLOAT));
    header.channels().insert("A", Channel(FLOAT));
    header.compression() = ZIP_COMPRESSION; // or ZIPS/PIZ/DWAA…

    FrameBuffer fb;
    const size_t xs = sizeof(float), ys = sizeof(float) * (size_t)w;

    fb.insert("R", Slice(FLOAT, (char*)r32.data(), xs, ys));
    fb.insert("G", Slice(FLOAT, (char*)g32.data(), xs, ys));
    fb.insert("B", Slice(FLOAT, (char*)b32.data(), xs, ys));
    fb.insert("A", Slice(FLOAT, (char*)a32.data(), xs, ys));

    // Use a single worker thread for deterministic behavior across toolchains.
    OutputFile file(path, header, 1);
    file.setFrameBuffer(fb);
    file.writePixels(h);
  } catch (const std::exception &e) {
    UNPROTECT(4);
    Rf_error("OpenEXR write error: %s", e.what());
  }

  UNPROTECT(4);
  return R_NilValue;
}

// ---------------------------------------------------------------------
// registration
static const R_CallMethodDef callTable[] = {
    {"C_read_exr", (DL_FUNC)&C_read_exr, 1},
    {"C_write_exr", (DL_FUNC)&C_write_exr, 7},
    {NULL, NULL, 0}};

extern "C" void R_init_libopenexr(DllInfo *dll) {
  R_registerRoutines(dll, NULL, callTable, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
