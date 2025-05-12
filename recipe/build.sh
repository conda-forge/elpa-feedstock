#!/usr/bin/env bash
set -ex

# Selected number of tests that can run on a CI machine
tests=(
  "validate_real_2stage_banded_default.sh"
)

if [ "${mpi}" != "nompi" ]; then
  MPI=yes
  SUFFIX=""
  export CXX="${BUILD_PREFIX}/bin/mpicxx" CC="${BUILD_PREFIX}/bin/mpicc" FC="${BUILD_PREFIX}/bin/mpifort"
else
  MPI=no
  SUFFIX="_onenode"
  export CXX="${BUILD_PREFIX}/bin/g++" CC="${BUILD_PREFIX}/bin/gcc" FC="${BUILD_PREFIX}/bin/gfortran"
fi

if [ "${mpi}" == "openmpi" ]; then
  export OMPI_MCA_plm=isolated
  export OMPI_MCA_btl_vader_single_copy_mechanism=none
  export OMPI_MCA_rmaps_base_oversubscribe=yes
fi

# fdep program uses FORTRAN_CPP ?= cpp -P -traditional -Wall -Werror
if [[ "$(uname)" = Darwin ]]; then
  export CFLAGS="-mavx ${CFLAGS}"
  export FFLAGS="-mavx ${FFLAGS}"
  export FORTRAN_CPP="${FC:-gfortran} -E -P -cpp"
  conf_extra="--disable-sse-assembly --disable-avx2"
else
  if [[ "$(uname -m)" = "x86_64" ]]; then
    export CFLAGS="-mavx2 -mfma ${CFLAGS}"
    export FFLAGS="-mavx2 -mfma ${FFLAGS}"
  else
    conf_extra="--disable-sse-assembly --disable-avx2 --disable-avx --disable-sse"
  fi
  export FORTRAN_CPP="${CPP:-cpp} -P -traditional"
fi

conf_options=(
   "--prefix=${PREFIX}"
   "--with-mpi=${MPI}"
   "--disable-avx512"
   "--disable-static" 
   "--enable-shared"
   ${conf_extra:-}
)

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export M4="${BUILD_PREFIX}/bin/m4"

./autogen.sh

# First build without OpenMP
mkdir build
pushd build
../configure "${conf_options[@]}"

make -j ${CPU_COUNT:-1}
for t in ${tests[@]}; do
  make $t && ./$t
done
make install

popd

# Second build with OpenMP
mkdir build_openmp
pushd build_openmp
../configure --enable-openmp "${conf_options[@]}"

make -j ${CPU_COUNT:-1}
for t in "${tests[@]}"; do
  make $t && ./$t
done
make install

popd
