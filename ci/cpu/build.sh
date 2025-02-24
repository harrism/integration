#!/bin/bash
# Copyright (c) 2020, NVIDIA CORPORATION.
###############################################################
# rapids meta/env pkg conda build script for gpuCI            #
#                                                             #
# config set in `ci/axis/*.yml`                               #
#                                                             #
# specifiy build type with env var `BUILD_PKGS`               #
#    - 'meta' - triggers meta-pkg builds                      #
#    - 'env' - triggers env-pkg builds                        #
#    - '' or undefined - trigers both                         #
###############################################################
set -e

# Set paths
export PATH="/opt/conda/bin:$PATH"
export HOME="$WORKSPACE"

# fixes https://github.com/mamba-org/mamba/issues/488
rm -f /opt/conda/pkgs/cache/*.json

# Set recipe paths
CONDA_XGBOOST_RECIPE="conda/recipes/rapids-xgboost"
CONDA_RAPIDS_RECIPE="conda/recipes/rapids"
CONDA_RAPIDS_BUILD_RECIPE="conda/recipes/rapids-build-env"
CONDA_RAPIDS_NOTEBOOK_RECIPE="conda/recipes/rapids-notebook-env"
CONDA_RAPIDS_DOC_RECIPE="conda/recipes/rapids-doc-env"

# Activate conda env
source activate base

# Print current env vars
env

# Install gpuCI tools
conda install -y --channel gpuci gpuci-tools boa

# Print diagnostic information
gpuci_logger "Print conda info..."
conda info
conda config --show-sources
conda list --show-channel-urls

export RAPIDS_DATE_STRING=$(date +%y%m%d)

# Get arch
ARCH=$(uname -m)

function build_pkg {
  # Build pkg
  gpuci_logger "Start conda build for '${1}'..."
  # TODO: Remove `--no-test` flag once importing on a CPU
  # node works correctly
  gpuci_conda_retry mambabuild \
    --no-test \
    --override-channels \
    --channel ${CONDA_USERNAME:-rapidsai-nightly} \
    --channel conda-forge \
    --channel nvidia \
    --python=${PYTHON_VER} \
    --variant-config-files ${CONDA_CONFIG_FILE} \
    ${1}
}

function run_builds {
  # Kick off main pkg build
  build_pkg $1
}

function upload_builds {

  # Check arch
  if [ "${ARCH}" = "x86_64" ]; then
    ARCH_DIR="linux-64"
  elif [ "${ARCH}" = "aarch64" ]; then
    ARCH_DIR="linux-aarch64"
  else
    echo "ERROR: Unsupported arch: ${ARCH}"
    exit 1
  fi

  # Check for upload key
  if [ -z "$MY_UPLOAD_KEY" ]; then
    gpuci_logger "No upload key found, env var MY_UPLOAD_KEY not set, skipping upload..."
  else
    gpuci_logger "Upload key found, starting upload..."
    gpuci_logger "Files to upload..."
    if [[ -n $(ls /tmp/conda-bld-output/${ARCH_DIR}/* | grep -i rapids.*.tar.bz2) ]]; then
      ls /tmp/conda-bld-output/${ARCH_DIR}/* | grep -i rapids.*.tar.bz2
    fi

    gpuci_logger "Starting upload..."
    if [[ -n $(ls /tmp/conda-bld-output/${ARCH_DIR}/* | grep -i rapids.*.tar.bz2) ]]; then
      ls /tmp/conda-bld-output/${ARCH_DIR}/* | grep -i rapids.*.tar.bz2 | xargs gpuci_retry \
        anaconda -t ${MY_UPLOAD_KEY} upload -u ${CONDA_USERNAME:-rapidsai-nightly} --label main --skip-existing --no-progress
    fi
  fi
}

if [[ "$BUILD_PKGS" == "meta" || -z "$BUILD_PKGS" ]] ; then
  # Run builds for meta-pkgs
  run_builds $CONDA_XGBOOST_RECIPE
  run_builds $CONDA_RAPIDS_RECIPE
fi

if [[ "$BUILD_PKGS" == "env" || -z "$BUILD_PKGS" ]] ; then
  # Run builds for env-pkgs
  run_builds $CONDA_RAPIDS_BUILD_RECIPE
  run_builds $CONDA_RAPIDS_NOTEBOOK_RECIPE
  # Bypass not supported packages for arm64
  if [ "${ARCH}" != "aarch64" ]; then
    run_builds $CONDA_RAPIDS_DOC_RECIPE
  fi
fi

# Upload builds
upload_builds
