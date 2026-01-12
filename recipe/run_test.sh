#!/bin/bash
set -ex

# MVAPICH-specific CUDA stub setup (only for testing on non-GPU CI runners)
if echo "${PKG_BUILD_STRING}" | grep -q "mpi_mvapich"; then
  if [[ "${target_platform}" == "linux-64" ]]; then
    export CUDA_HOME="${PREFIX}/targets/x86_64-linux"
  elif [[ "${target_platform}" == "linux-aarch64" ]]; then
    export CUDA_HOME="${PREFIX}/targets/sbsa-linux"
  else
    # Skip setup on unsupported platforms
    true
  fi

  mkdir -p "${CUDA_HOME}/lib/stubs"
  export LD_LIBRARY_PATH="${CUDA_HOME}/lib/stubs:${LD_LIBRARY_PATH:-}"
  ln -sf "${CUDA_HOME}/lib/stubs/libcuda.so" "${CUDA_HOME}/lib/stubs/libcuda.so.1" || true
  export MPIR_CVAR_ENABLE_GPU=0
fi

# pkg-config version checks (translated from the original with selector logic)
if [[ "${target_platform}" != "linux-aarch64" ]]; then
  pkg-config elpa --exact-version "${PKG_VERSION}"
fi
pkg-config elpa_openmp --exact-version "${PKG_VERSION}"

# Run the kernel printing tools to verify available kernels
elpa2_print_kernels_openmp

if [[ "${target_platform}" != "linux-aarch64" ]]; then
  elpa2_print_kernels
fi
