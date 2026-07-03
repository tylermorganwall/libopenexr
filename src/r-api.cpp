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
#include <ImfStandardAttributes.h>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <vector>

using namespace OPENEXR_IMF_NAMESPACE;
using namespace IMATH_NAMESPACE;

// ---------------------------------------------------------------------
// helpers
inline void check_bool(bool ok, const char *msg) {
  if (!ok)
    Rf_error("%s", msg);
}

inline SEXP get_list_element(SEXP list, const char *name) {
  SEXP names = Rf_getAttrib(list, R_NamesSymbol);
  if (TYPEOF(names) != STRSXP)
    return R_NilValue;

  const R_xlen_t n = Rf_xlength(list);
  for (R_xlen_t i = 0; i < n; ++i) {
    if (std::strcmp(CHAR(STRING_ELT(names, i)), name) == 0)
      return VECTOR_ELT(list, i);
  }

  return R_NilValue;
}

inline const double *checked_real_vector(SEXP value, R_xlen_t length,
                                         const char *label) {
  if (TYPEOF(value) != REALSXP || Rf_xlength(value) != length) {
    Rf_error("`%s` must be a numeric vector of length %lld", label,
             (long long)length);
  }

  const double *data = REAL(value);
  for (R_xlen_t i = 0; i < length; ++i) {
    if (!std::isfinite(data[i]))
      Rf_error("`%s` must contain only finite values", label);
  }

  return data;
}

void set_xy_vector(SEXP list, int index, const V2f &value) {
  SEXP xy = PROTECT(Rf_allocVector(REALSXP, 2));
  REAL(xy)[0] = value.x;
  REAL(xy)[1] = value.y;

  SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(names, 0, Rf_mkChar("x"));
  SET_STRING_ELT(names, 1, Rf_mkChar("y"));
  Rf_setAttrib(xy, R_NamesSymbol, names);

  SET_VECTOR_ELT(list, index, xy);
  UNPROTECT(2);
}

void set_chromaticities_metadata(SEXP metadata, int index,
                                 const Chromaticities &value) {
  SEXP chromaticities = PROTECT(Rf_allocVector(VECSXP, 4));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, 4));
  SET_STRING_ELT(names, 0, Rf_mkChar("red"));
  SET_STRING_ELT(names, 1, Rf_mkChar("green"));
  SET_STRING_ELT(names, 2, Rf_mkChar("blue"));
  SET_STRING_ELT(names, 3, Rf_mkChar("white"));
  Rf_setAttrib(chromaticities, R_NamesSymbol, names);

  set_xy_vector(chromaticities, 0, value.red);
  set_xy_vector(chromaticities, 1, value.green);
  set_xy_vector(chromaticities, 2, value.blue);
  set_xy_vector(chromaticities, 3, value.white);

  SET_VECTOR_ELT(metadata, index, chromaticities);
  UNPROTECT(2);
}

void set_adopted_neutral_metadata(SEXP metadata, int index, const V2f &value) {
  SEXP adoptedNeutral = PROTECT(Rf_allocVector(REALSXP, 2));
  REAL(adoptedNeutral)[0] = value.x;
  REAL(adoptedNeutral)[1] = value.y;

  SEXP names = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(names, 0, Rf_mkChar("x"));
  SET_STRING_ELT(names, 1, Rf_mkChar("y"));
  Rf_setAttrib(adoptedNeutral, R_NamesSymbol, names);

  SET_VECTOR_ELT(metadata, index, adoptedNeutral);
  UNPROTECT(2);
}

const char *envmap_name(Envmap value) {
  switch (value) {
  case ENVMAP_LATLONG:
    return "latlong";
  case ENVMAP_CUBE:
    return "cube";
  default:
    return "unknown";
  }
}

// Returns one protected object; caller must UNPROTECT it.
SEXP build_metadata_list(const Header &header) {
  int metadata_count = 0;
  metadata_count += hasChromaticities(header) ? 1 : 0;
  metadata_count += hasAdoptedNeutral(header) ? 1 : 0;
  metadata_count += hasWhiteLuminance(header) ? 1 : 0;
  metadata_count += hasEnvmap(header) ? 1 : 0;

  SEXP metadata = PROTECT(Rf_allocVector(VECSXP, metadata_count));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, metadata_count));

  int index = 0;
  if (hasChromaticities(header)) {
    SET_STRING_ELT(names, index, Rf_mkChar("chromaticities"));
    set_chromaticities_metadata(metadata, index, chromaticities(header));
    ++index;
  }
  if (hasAdoptedNeutral(header)) {
    SET_STRING_ELT(names, index, Rf_mkChar("adoptedNeutral"));
    set_adopted_neutral_metadata(metadata, index, adoptedNeutral(header));
    ++index;
  }
  if (hasWhiteLuminance(header)) {
    SET_STRING_ELT(names, index, Rf_mkChar("whiteLuminance"));
    SEXP value = PROTECT(Rf_ScalarReal(whiteLuminance(header)));
    SET_VECTOR_ELT(metadata, index, value);
    UNPROTECT(1);
    ++index;
  }
  if (hasEnvmap(header)) {
    SET_STRING_ELT(names, index, Rf_mkChar("envmap"));
    SEXP value = PROTECT(Rf_mkString(envmap_name(envmap(header))));
    SET_VECTOR_ELT(metadata, index, value);
    UNPROTECT(1);
  }

  Rf_setAttrib(metadata, R_NamesSymbol, names);
  UNPROTECT(1);
  return metadata;
}

void add_metadata_to_header(Header &header, SEXP metadata) {
  if (Rf_isNull(metadata))
    return;

  check_bool(TYPEOF(metadata) == VECSXP, "`metadata` must be a list");

  SEXP chromaticities_SEXP = get_list_element(metadata, "chromaticities");
  if (!Rf_isNull(chromaticities_SEXP)) {
    const double *value =
        checked_real_vector(chromaticities_SEXP, 8, "metadata$chromaticities");
    addChromaticities(
        header,
        Chromaticities(V2f(value[0], value[1]), V2f(value[2], value[3]),
                       V2f(value[4], value[5]), V2f(value[6], value[7])));
  }

  SEXP adoptedNeutral_SEXP = get_list_element(metadata, "adoptedNeutral");
  if (!Rf_isNull(adoptedNeutral_SEXP)) {
    const double *value =
        checked_real_vector(adoptedNeutral_SEXP, 2, "metadata$adoptedNeutral");
    addAdoptedNeutral(header, V2f(value[0], value[1]));
  }

  SEXP whiteLuminance_SEXP = get_list_element(metadata, "whiteLuminance");
  if (!Rf_isNull(whiteLuminance_SEXP)) {
    const double *value =
        checked_real_vector(whiteLuminance_SEXP, 1, "metadata$whiteLuminance");
    addWhiteLuminance(header, static_cast<float>(value[0]));
  }

  SEXP envmap_SEXP = get_list_element(metadata, "envmap");
  if (!Rf_isNull(envmap_SEXP)) {
    if (TYPEOF(envmap_SEXP) != INTSXP || Rf_xlength(envmap_SEXP) != 1) {
      Rf_error("`metadata$envmap` must be an integer scalar");
    }

    const int value = INTEGER(envmap_SEXP)[0];
    if (value == 0) {
      addEnvmap(header, ENVMAP_LATLONG);
    } else if (value == 1) {
      addEnvmap(header, ENVMAP_CUBE);
    } else {
      Rf_error("`metadata$envmap` must be 0 or 1");
    }
  }
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

    SEXP metadata = build_metadata_list(hdr);
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 7));
    SET_VECTOR_ELT(out, 0, rMat);
    SET_VECTOR_ELT(out, 1, gMat);
    SET_VECTOR_ELT(out, 2, bMat);
    SET_VECTOR_ELT(out, 3, aMat);
    SET_VECTOR_ELT(out, 4, Rf_ScalarInteger(w));
    SET_VECTOR_ELT(out, 5, Rf_ScalarInteger(h));
    SET_VECTOR_ELT(out, 6, metadata);
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 7));
    const char *nms[7] = {"r","g","b","a","width","height","metadata"};
    for (int i=0;i<7;++i) SET_STRING_ELT(names, i, Rf_mkChar(nms[i]));
    Rf_setAttrib(out, R_NamesSymbol, names);

    UNPROTECT(7);
    return out;
  } catch (const std::exception &e) {
    Rf_error("OpenEXR read error: %s", e.what());
  }
}

// ---------------------------------------------------------------------
// .Call("C_write_exr", path, r, g, b, a, width, height, metadata)
extern "C" SEXP C_write_exr(SEXP path_SEXP, SEXP rMat, SEXP gMat, SEXP bMat,
                            SEXP aMat, SEXP w_SEXP, SEXP h_SEXP,
                            SEXP metadata_SEXP) {
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
    header.compression() = ZIP_COMPRESSION;
    add_metadata_to_header(header, metadata_SEXP);

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
    {"C_write_exr", (DL_FUNC)&C_write_exr, 8},
    {NULL, NULL, 0}};

extern "C" void R_init_libopenexr(DllInfo *dll) {
  R_registerRoutines(dll, NULL, callTable, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
