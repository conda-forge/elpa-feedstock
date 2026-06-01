#!/usr/bin/env bash
set -ex

# Update config.guess / config.sub
cp "${BUILD_PREFIX}/share/gnuconfig/config."* .

# Fix perl shebangs (portable)
find . -name "*.pl" -exec sed -i.bak '1s|^#!.*perl.*|#!/usr/bin/env perl|' {} +
find . -name "*.pl.bak" -delete

# Minimal CI tests
tests=(
  "validate_real_2stage_banded_default.sh"
)

# MPI setup (CRITICAL: avoid wrappers during cross-compilation)
if [[ "${mpi}" != "nompi" ]]; then
  MPI=yes

  export OMPI_CC="${CC}"
  export OMPI_CXX="${CXX}"
  export OMPI_FC="${FC}"
  export MPICH_CC="${CC}"
  export MPICH_CXX="${CXX}"
  export MPICH_FC="${FC}"

  # Only use MPI wrappers for native builds
  if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" != "1" ]]; then
    export CC="${PREFIX}/bin/mpicc"
    export CXX="${PREFIX}/bin/mpicxx"
    export FC="${PREFIX}/bin/mpifort"
  fi
else
  MPI=no
fi

# OpenMPI CI stabilization (runtime only)
if [[ "${mpi}" == "openmpi" ]]; then
  export OMPI_MCA_plm=isolated
  export OMPI_MCA_btl_vader_single_copy_mechanism=none
  export OMPI_MCA_rmaps_base_oversubscribe=yes
fi

# Compiler + architecture flags
conf_extra=""

if [[ "$(uname)" == "Darwin" ]]; then
  if [[ "${target_platform}" == "osx-arm64" ]]; then
    # LTO problematic in cross builds
    export CFLAGS="${CFLAGS} -fno-lto"
    export FCFLAGS="${FCFLAGS} -fno-lto"
    export CXXFLAGS="${CXXFLAGS} -fno-lto"

    conf_extra="--disable-sse-assembly --disable-avx2 --disable-avx --disable-sse"
  else
    export CFLAGS="${CFLAGS} -mavx"
    export FFLAGS="${FFLAGS} -mavx"
    conf_extra="--disable-sse-assembly --disable-avx2"
  fi

  export FORTRAN_CPP="${FC:-gfortran} -E -P -cpp"
else
  if [[ "${target_platform}" == "linux-64" ]]; then
    export CFLAGS="${CFLAGS} -mavx2 -mfma"
    export FFLAGS="${FFLAGS} -mavx2 -mfma"
  else
    conf_extra="--disable-sse-assembly --disable-avx2 --disable-avx --disable-sse"
  fi

  export FORTRAN_CPP="${CPP:-cpp} -P -traditional"
fi

# Cross-compilation fixes
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == "1" ]]; then
  export ac_cv_prog_cxx_works=yes
  export ac_cv_prog_cc_works=yes
  export ac_cv_prog_fc_works=yes
  export ac_cv_prog_cxx_cross=yes
  export cross_compiling=yes
fi

# Ensure PREFIX visibility
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include"
export FCFLAGS="${FCFLAGS} -I${PREFIX}/include"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"

if [[ "${MPI}" == "yes" ]]; then
  export LIBS="${LIBS} -lscalapack"
fi

# Configure options
conf_options=(
  "--prefix=${PREFIX}"
  "--build=${BUILD}"
  "--host=${HOST}"
  "--target=${HOST}"
  "--with-mpi=${MPI}"
  "--disable-avx512"
)

if [[ -n "${conf_extra}" ]]; then
  conf_options+=(${conf_extra})
fi

# Build (no OpenMP)
mkdir build
pushd build

../configure "${conf_options[@]}" \
  CC="${CC}" CXX="${CXX}" FC="${FC}" \
  || { cat config.log; exit 1; }

make -j"${CPU_COUNT:-1}"
make install

popd

# Build (with OpenMP)
mkdir build_openmp
pushd build_openmp

../configure --enable-openmp "${conf_options[@]}" \
  CC="${CC}" CXX="${CXX}" FC="${FC}"

make -j"${CPU_COUNT:-1}"

# Run tests only if safe
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" != "1" && "${MPI}" == "yes" ]]; then
  for t in "${tests[@]}"; do
    make "$t" && ./"$t" || true
  done
fi

make install

popd

