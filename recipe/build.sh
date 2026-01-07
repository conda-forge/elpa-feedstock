#!/usr/bin/env bash
# Get an updated config.sub and config.guess
cp $BUILD_PREFIX/share/gnuconfig/config.* .
set -ex

# Selected number of tests that can run on a CI machine
tests=(
  "validate_real_2stage_banded_default.sh"
)

if [ "${mpi}" != "nompi" ]; then
  MPI=yes
  SUFFIX=""
  export CXX="$BUILD_PREFIX/bin/mpicxx"
  export CC="$BUILD_PREFIX/bin/mpicc"
  export FC="$BUILD_PREFIX/bin/mpifort"
else
  MPI=no
  SUFFIX="_onenode"
fi

if [ "${mpi}" == "openmpi" ]; then
  export OMPI_MCA_plm=isolated
  export OMPI_MCA_btl_vader_single_copy_mechanism=none
  export OMPI_MCA_rmaps_base_oversubscribe=yes
fi

# fdep program uses FORTRAN_CPP ?= cpp -P -traditional -Wall -Werror
if [[ "$(uname)" = Darwin ]]; then
  if [[ "${target_platform}" == osx-arm64 ]]; then
    export CFLAGS="${CFLAGS} -fno-lto"
    export FCFLAGS="${FCFLAGS} -fno-lto"
    export CXXFLAGS="${CXXFLAGS} -fno-lto"
    conf_extra="--disable-sse-assembly --disable-avx2 --disable-avx --disable-sse"
  else
    export CFLAGS="-mavx ${CFLAGS}"
    export FFLAGS="-mavx ${FFLAGS}"
    conf_extra="--disable-sse-assembly --disable-avx2"
  fi
  export FORTRAN_CPP="${FC:-gfortran} -E -P -cpp"
else
  if [[ "$(uname -m)" = "x86_64" ]]; then
    export CFLAGS="-mavx2 -mfma ${CFLAGS}"
    export FFLAGS="-mavx2 -mfma ${FFLAGS}"
  else
    conf_extra="--disable-sse-assembly --disable-avx2 --disable-avx --disable-sse"
  fi
  export FORTRAN_CPP="${CPP:-cpp} -P -traditional"
fi

# Base options used by both builds
base_options=(
   "--prefix=${PREFIX}"
   "--build=${BUILD}"
   "--host=${HOST}"
   "--with-mpi=${MPI}"
   "--disable-avx512"
   ${conf_extra:-}
)

if [[ "${target_platform}" == "linux-aarch64" ]]; then
  base_options+=("--enable-neon-arch64-kernels")
fi

# Test disabling on aarch64
test_extra=()
if [[ "${target_platform}" == "linux-aarch64" ]]; then
  test_extra=( "--disable-fortran-tests" "--disable-c-tests" "--disable-cpp-tests" )
fi

# CUDA-specific options (only for mvapich)
cuda_options=()
if [[ "${mpi}" == "mvapich" ]]; then
  source ${RECIPE_DIR}/mvapich_cuda_stub.sh

  if [[ "${target_platform}" == "linux-aarch64" ]]; then
    cuda_options=(
      "--enable-nvidia-gpu-kernels"
      "--enable-nvidia-sm90-gpu-kernels"
      "--with-NVIDIA-GPU-compute-capability=sm_90"
      "--enable-cuda-aware-mpi=yes"
      "--with-cuda-path=${CUDA_HOME}"
    )
  else
    cuda_options=(
      "--enable-nvidia-gpu-kernels"
      "--enable-nvidia-sm80-gpu-kernels"
      "--with-NVIDIA-GPU-compute-capability=sm_80"
      "--enable-cuda-aware-mpi=yes"
      "--with-cuda-path=${CUDA_HOME}"
    )
  fi

  export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib -L${CUDA_HOME}/lib -L${CUDA_HOME}/lib/stubs"
fi

# Non-OpenMP build (skip on aarch64)
if [[ "${target_platform}" != "linux-aarch64" ]]; then
  mkdir build
  pushd build
  ../configure "${base_options[@]}" "${cuda_options[@]}" "${test_extra[@]}"
  make -j ${CPU_COUNT:-1}
  make install
  popd
fi

# OpenMP build (always)
mkdir build_openmp
pushd build_openmp

../configure --enable-openmp "${base_options[@]}" "${cuda_options[@]}" "${test_extra[@]}"

make -j ${CPU_COUNT:-1}

if [[ "${target_platform}" != "linux-aarch64" ]] && [[ "${mpi}" != "mvapich" ]]; then
  for t in ${tests[@]}; do
    make $t && ./$t
  done
fi

make install
popd

if [[ ${mpi} == "mvapich" ]]; then
  rm -f "${CUDA_HOME}/lib/stubs/libcuda.so.1"
  rm -f "${CUDA_HOME}/lib/libcublas.so"
  rm -f "${CUDA_HOME}/lib/libcusolver.so"
fi
