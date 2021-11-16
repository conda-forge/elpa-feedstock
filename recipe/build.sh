#!/usr/bin/env bash
set -ex

# Selected number of tests that can run on a CI machine
tests=(
  "validate_real_2stage_banded_default.sh"
)

if [ "${mpi}" != "nompi" ]; then
  MPI=yes
  SUFFIX=""
  export CXX="$PREFIX/bin/mpicxx" CC="$PREFIX/bin/mpicc" FC="$PREFIX/bin/mpifort"
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
  export CFLAGS="-mavx ${CFLAGS}"
  export FFLAGS="-mavx ${FFLAGS}"
  export FORTRAN_CPP="${FC:-gfortran} -E -P -cpp"
  conf_extra="--disable-sse-assembly --disable-avx2"
else
  export CFLAGS="-mavx2 -mfma ${CFLAGS}"
  export FFLAGS="-mavx2 -mfma ${FFLAGS}"
  export FORTRAN_CPP="${CPP:-cpp} -P -traditional"
fi

conf_options=(
   "--prefix=${PREFIX}"
   "--with-mpi=${MPI}"
   "--disable-avx512"
   ${conf_extra:-}
)

# First build without OpenMP
mkdir build
pushd build
../configure "${conf_options[@]}"

make -j ${CPU_COUNT:-1}
for t in ${tests[@]}; do
  make $t && ./$t
done
make install

# Create a pkg-config file without version suffix as well
cp ${PREFIX}/lib/pkgconfig/elpa${SUFFIX}{-*,}.pc

popd

# Second build with OpenMP
mkdir build_openmp
pushd build_openmp
../configure --enable-openmp "${conf_options[@]}"

make -j ${CPU_COUNT:-1}
for t in ${tests[@]}; do
  make $t && timeout 30 ./$t
done
make install

# Create a pkg-config file without version suffix as well
cp ${PREFIX}/lib/pkgconfig/elpa${SUFFIX}_openmp{-*,}.pc

popd
