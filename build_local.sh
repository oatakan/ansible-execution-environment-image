#!/bin/bash
set -e

# Usage: ./build_local.sh [ee_name]
# Example: ./build_local.sh ansible-base-ee-2.16

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_ROOT="${SCRIPT_DIR}"
LOCAL_BUILD_ENV_FILE="${REPO_ROOT}/.ee-build.env"

resolve_repo_path() {
    local path="${1:-}"
    if [ -z "$path" ]; then
        return 1
    fi
    case "$path" in
        ~)
            printf '%s\n' "$HOME"
            ;;
        ~/*)
            printf '%s\n' "$HOME/${path#~/}"
            ;;
        /*)
            printf '%s\n' "$path"
            ;;
        *)
            printf '%s\n' "$REPO_ROOT/$path"
            ;;
    esac
}

EE_DIR=${1:-ansible-base-ee-2.16}
TAG="${EE_DIR}:latest"
EE_BUILD_ENV_FILE=$(resolve_repo_path "${EE_BUILD_ENV_FILE:-$LOCAL_BUILD_ENV_FILE}")
TMP_RHN_TOKEN_FILE=""

cleanup() {
    if [ -n "$TMP_RHN_TOKEN_FILE" ] && [ -f "$TMP_RHN_TOKEN_FILE" ]; then
        rm -f "$TMP_RHN_TOKEN_FILE"
    fi
}
trap cleanup EXIT

ANSIBLE_BUILDER_BIN=${ANSIBLE_BUILDER_BIN:-}
if [ -z "$ANSIBLE_BUILDER_BIN" ]; then
    if command -v ansible-builder >/dev/null 2>&1; then
        ANSIBLE_BUILDER_BIN=$(command -v ansible-builder)
    elif [ -x "$REPO_ROOT/.venv/bin/ansible-builder" ]; then
        ANSIBLE_BUILDER_BIN="$REPO_ROOT/.venv/bin/ansible-builder"
    else
        echo "Error: ansible-builder not found. Install it or set ANSIBLE_BUILDER_BIN." >&2
        exit 1
    fi
fi

if [ -f "$EE_BUILD_ENV_FILE" ]; then
    echo "Loading build config from $EE_BUILD_ENV_FILE"
    set -a
    . "$EE_BUILD_ENV_FILE"
    set +a
fi

if [ -z "${RHN_CS_API_OFFLINE_TOKEN:-}" ] && [ -n "${EE_BUILD_SECRETS_FILE:-}" ]; then
    EE_BUILD_SECRETS_FILE=$(resolve_repo_path "$EE_BUILD_SECRETS_FILE")
    if [ -f "$EE_BUILD_SECRETS_FILE" ]; then
        echo "Loading build secrets from configured file"
        set -a
        . "$EE_BUILD_SECRETS_FILE"
        set +a
    else
        echo "Warning: configured build secrets file not found." >&2
    fi
fi

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

BUILD_ARGS=(build -v 3 --context="$EE_DIR" --tag="$TAG" --container-runtime="$RUNTIME")

if [ -n "${RHN_CS_API_OFFLINE_TOKEN:-}" ]; then
    TMP_RHN_TOKEN_FILE=$(mktemp)
    chmod 600 "$TMP_RHN_TOKEN_FILE"
    printf '%s' "$RHN_CS_API_OFFLINE_TOKEN" > "$TMP_RHN_TOKEN_FILE"
    BUILD_ARGS+=(--extra-build-cli-args "--secret id=rhn_cs_api_offline_token,src=$TMP_RHN_TOKEN_FILE")
    echo "RHN_CS_API_OFFLINE_TOKEN detected; optional Red Hat certified collections will be installed."
else
    echo "RHN_CS_API_OFFLINE_TOKEN not set; optional Red Hat certified collections will be skipped."
fi

echo "Using container runtime: $RUNTIME"
if [ "$RUNTIME" = "docker" ]; then
    DOCKER_BUILDKIT=1 "$ANSIBLE_BUILDER_BIN" "${BUILD_ARGS[@]}"
else
    "$ANSIBLE_BUILDER_BIN" "${BUILD_ARGS[@]}"
fi

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
