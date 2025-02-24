#!/bin/bash
set -e

CONDA_ENV_NAME="rapids${RAPIDS_VER}_cuda${CUDA_VER}_py${PYTHON_VER}"

echo "Install conda-pack"
rapids-mamba-retry install -n base -c conda-forge "conda-pack"

echo "Creating conda environment $CONDA_ENV_NAME"
rapids-mamba-retry create -y -n $CONDA_ENV_NAME \
    -c $CONDA_USERNAME -c conda-forge -c nvidia \
    "rapids=$RAPIDS_VER" \
    "cudatoolkit=$CUDA_VER" \
    "python=$PYTHON_VER"

echo "Packing conda environment"
conda-pack --quiet --ignore-missing-files -n "$CONDA_ENV_NAME" -o "${CONDA_ENV_NAME}.tar.gz"

export AWS_DEFAULT_REGION="us-east-2"
echo "Upload packed conda"
aws s3 cp --only-show-errors --acl public-read "${CONDA_ENV_NAME}.tar.gz" "s3://rapidsai-data/conda-pack/${CONDA_USERNAME}/${CONDA_ENV_NAME}.tar.gz"
