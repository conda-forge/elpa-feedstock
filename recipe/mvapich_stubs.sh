#!/bin/bash
set -e

if [[ "${target_platform}" == "linux-64" ]]; then
  export CUDA_HOME="${PREFIX}/targets/x86_64-linux"
elif [[ "${target_platform}" == "linux-aarch64" ]]; then
  export CUDA_HOME="${PREFIX}/targets/sbsa-linux"
fi
mkdir -p "${CUDA_HOME}/lib/stubs"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib/stubs:${LD_LIBRARY_PATH}"
ln -sf "${CUDA_HOME}/lib/stubs/libcuda.so" "${CUDA_HOME}/lib/stubs/libcuda.so.1"
export MPIR_CVAR_ENABLE_GPU=0
