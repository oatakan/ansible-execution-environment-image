#!/usr/bin/env bash
set -euo pipefail

# Reproduce the GitHub Actions build locally.
# Mirrors .github/workflows/deploy.yml:
#   - pip install -r requirements.txt
#   - ansible-builder create -v 3 --context=context --output-filename=Dockerfile
#   - docker buildx build (multi-arch) with provenance/sbom disabled
#
# Usage:
#   ./build_ci_like.sh ansible-base-ee-main
#   ./build_ci_like.sh ansible-base-ee-dev --platforms linux/amd64,linux/arm64
#   ./build_ci_like.sh ansible-base-ee-main --platforms linux/amd64 --load
#
# Notes (macOS/Apple Silicon):
#   - Use --platforms linux/amd64 to match CI and avoid host-arch drift.
#   - Multi-arch builds cannot be --load'ed; this script will export an OCI artifact instead.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT="${SCRIPT_DIR}"
LOCAL_BUILD_ENV_FILE="${REPO_ROOT}/.ee-build.env"
LOCAL_ANSIBLE_BUILDER_BIN="${REPO_ROOT}/.venv/bin/ansible-builder"

resolve_repo_path() {
  local path="${1:-}"
  if [[ -z "${path}" ]]; then
    return 1
  fi
  case "${path}" in
    ~)
      path="${HOME}"
      ;;
    ~/*)
      path="${HOME}/${path#~/}"
      ;;
  esac
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${REPO_ROOT}/${path}"
  fi
}

EE_DIR=${1:-}
shift || true

if [[ -z "${EE_DIR}" ]]; then
  echo "Usage: $0 <ee-folder> [--platforms <csv>] [--tag <name:tag>] [--push] [--load] [--no-qemu] [--no-cache]" >&2
  exit 2
fi

if [[ ! -d "${EE_DIR}" ]]; then
  echo "Error: Directory '${EE_DIR}' does not exist." >&2
  exit 2
fi

EE_BUILD_ENV_FILE="$(resolve_repo_path "${EE_BUILD_ENV_FILE:-${LOCAL_BUILD_ENV_FILE}}")"
if [[ -f "${EE_BUILD_ENV_FILE}" ]]; then
  echo "Info: loading build config from ${EE_BUILD_ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  source "${EE_BUILD_ENV_FILE}"
  set +a
fi

if [[ -z "${RHN_CS_API_OFFLINE_TOKEN:-}" && -n "${EE_BUILD_SECRETS_FILE:-}" ]]; then
  EE_BUILD_SECRETS_FILE="$(resolve_repo_path "${EE_BUILD_SECRETS_FILE}")"
  if [[ -f "${EE_BUILD_SECRETS_FILE}" ]]; then
    echo "Info: loading build secrets from configured file"
    set -a
    # shellcheck disable=SC1090
    source "${EE_BUILD_SECRETS_FILE}"
    set +a
  else
    echo "Warning: configured build secrets file not found." >&2
  fi
fi

PLATFORMS=""
TAG="${EE_DIR}:ci-local"
PUSH=false
LOAD=false
SETUP_QEMU=true
NO_CACHE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platforms)
      PLATFORMS=${2:-}
      shift 2
      ;;
    --tag)
      TAG=${2:-}
      shift 2
      ;;
    --push)
      PUSH=true
      shift
      ;;
    --load)
      LOAD=true
      shift
      ;;
    --no-qemu)
      SETUP_QEMU=false
      shift
      ;;
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^#//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found. Install Docker Desktop first." >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "Error: docker buildx not available. Enable Buildx in Docker Desktop." >&2
  exit 1
fi

# Defaults to match repo workflows
if [[ -z "${PLATFORMS}" ]]; then
  case "${EE_DIR}" in
    ansible-base-ee-main)
      PLATFORMS="linux/amd64"
      ;;
    ansible-base-ee-dev|ansible-base-ee-2.16)
      PLATFORMS="linux/amd64,linux/arm64"
      ;;
    *)
      PLATFORMS="linux/amd64"
      ;;
  esac
fi

echo "[1/3] Generating build context via ansible-builder..."
run_ansible_builder_create() {
  # Prefer a locally installed ansible-builder if available; otherwise run it in a
  # container to avoid local Python version/package constraints and to better
  # match CI behavior.
  if command -v ansible-builder >/dev/null 2>&1; then
    (
      cd "${EE_DIR}"
      rm -rf context
      ansible-builder create -v 3 --context=context --output-filename=Dockerfile
    )
    return 0
  fi

  if [[ -x "${LOCAL_ANSIBLE_BUILDER_BIN}" ]]; then
    (
      cd "${EE_DIR}"
      rm -rf context
      "${LOCAL_ANSIBLE_BUILDER_BIN}" create -v 3 --context=context --output-filename=Dockerfile
    )
    return 0
  fi

  echo "Info: ansible-builder not found locally; running it in python:3.12-bookworm"
  docker run --rm \
    -v "${PWD}:/work" \
    -w /work \
    python:3.12-bookworm \
    bash -lc "set -euo pipefail; pip install -q -r requirements.txt; cd '${EE_DIR}'; rm -rf context; ansible-builder create -v 3 --context=context --output-filename=Dockerfile"
}

# Match CI: create build files into <EE_DIR>/context
echo "[1/3] Generating build context via ansible-builder..."
run_ansible_builder_create

# Match CI: setup QEMU for multi-arch (safe even on amd64-only builds)
if [[ "${SETUP_QEMU}" == "true" ]]; then
  echo "[2/3] Ensuring binfmt/QEMU is available for cross-builds..."
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true
fi

# Ensure we have a usable buildx builder selected
BUILDER_NAME="ci-local"
if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER_NAME}" --use >/dev/null
else
  docker buildx use "${BUILDER_NAME}" >/dev/null
fi

echo "[3/3] Building with buildx (platforms: ${PLATFORMS})..."
BUILD_ARGS=(
  build
  --progress=plain
  --provenance=false
  --sbom=false
  --platform "${PLATFORMS}"
  -t "${TAG}"
  -f "${EE_DIR}/context/Dockerfile"
  "${EE_DIR}/context"
)

if [[ -n "${RHN_CS_API_OFFLINE_TOKEN:-}" ]]; then
  BUILD_ARGS+=(--secret "id=rhn_cs_api_offline_token,env=RHN_CS_API_OFFLINE_TOKEN")
  echo "Info: RHN_CS_API_OFFLINE_TOKEN detected; optional Red Hat certified collections will be installed."
else
  echo "Info: RHN_CS_API_OFFLINE_TOKEN not set; optional Red Hat certified collections will be skipped."
fi

if [[ "${NO_CACHE}" == "true" ]]; then
  BUILD_ARGS+=(--no-cache)
fi

if [[ "${PUSH}" == "true" ]]; then
  BUILD_ARGS+=(--push)
else
  # If single-platform build, allow --load for rapid iteration.
  if [[ "${LOAD}" == "true" ]]; then
    if [[ "${PLATFORMS}" == *","* ]]; then
      echo "Error: --load only works for single-platform builds. Remove extra platforms or omit --load." >&2
      exit 2
    fi
    BUILD_ARGS+=(--load)
  else
    # Multi-arch without push: export as OCI artifact so the build still runs fully.
    if [[ "${PLATFORMS}" == *","* ]]; then
      OUT="${EE_DIR}.oci.tar"
      rm -f "${OUT}"
      BUILD_ARGS+=(--output "type=oci,dest=${OUT}")
      echo "Info: multi-arch build output will be written to ${OUT}"
    fi
  fi
fi

docker buildx "${BUILD_ARGS[@]}"

echo "Done. Tag: ${TAG}"
if [[ "${PUSH}" != "true" && "${LOAD}" == "true" ]]; then
  echo "To smoke-test: docker run --rm ${TAG} ansible --version"
fi
