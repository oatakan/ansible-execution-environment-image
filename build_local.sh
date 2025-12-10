#!/bin/bash
set -e

# Usage: ./build_local.sh [ee_name]
# Example: ./build_local.sh ansible-base-ee-2.16

EE_DIR=${1:-ansible-base-ee-2.16}
TAG="${EE_DIR}:latest"

# Get the absolute path of the repo root
REPO_ROOT=$(pwd)

if [ ! -d "$EE_DIR" ]; then
    echo "Error: Directory $EE_DIR does not exist."
    echo "Available directories:"
    ls -d ansible-base-ee-*
    exit 1
fi

echo "=========================================="
echo "Building Execution Environment: $EE_DIR"
echo "Tag: $TAG"
echo "=========================================="

# Change to the EE directory
cd "$EE_DIR"

# Run ansible-builder
# Matches the project pattern where context dir name == parent dir name
# Force docker runtime if available, otherwise fallback to podman
RUNTIME="podman"
if command -v docker &> /dev/null; then
    RUNTIME="docker"
fi

echo "Using container runtime: $RUNTIME"
ansible-builder build -v 3 --context="$EE_DIR" --tag="$TAG" --container-runtime="$RUNTIME"

echo "=========================================="
echo "Verifying image..."
echo "=========================================="

# Run a simple verification command
if command -v docker &> /dev/null; then
    docker run --rm "$TAG" ansible --version
elif command -v podman &> /dev/null; then
    podman run --rm "$TAG" ansible --version
else
    echo "Warning: Neither docker nor podman found. Skipping verification."
fi

echo "=========================================="
echo "Build complete: $TAG"
echo "=========================================="
