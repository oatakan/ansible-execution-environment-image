# Ansible Execution Environment Images

This repository contains the definitions and build configurations for custom Ansible Execution Environments (EEs). These images are built using `ansible-builder` and are designed to be used with Ansible Automation Platform (AAP) or AWX.

## 📦 Available Environments

| Environment | Directory | Base Image | Ansible Core | Description |
|-------------|-----------|------------|--------------|-------------|
| **Dev** | `ansible-base-ee-dev` | `centos:stream9` | `2.16 - 2.18` | Development environment with newer core versions and Python 3.12. |
| **Main** | `ansible-base-ee-main` | `ansible-runner:latest` | `2.13 - 2.15` | Stable environment based on the official runner image. |
| **Legacy 2.16** | `ansible-base-ee-2.16` | `centos:stream9` | `~2.16` | Pinned to Ansible Core 2.16 to support legacy managed nodes (e.g., RHEL 8 / Python 3.6). |

## 🚀 Getting Started

### Prerequisites

* **Container Runtime**: [Docker](https://docs.docker.com/get-docker/) or [Podman](https://podman.io/getting-started/installation).
* **Python**: Python 3.9+ installed.
* **Ansible Builder**:

  ```bash
  pip install ansible-builder
  ```

### 🛠️ Local Development

A helper script `build_local.sh` is provided to simplify the local build process. It automatically detects your container runtime (Docker/Podman) and builds the specified environment.

**Usage:**

```bash
# Build a specific environment (e.g., 2.16)
./build_local.sh ansible-base-ee-2.16

# Build the dev environment
./build_local.sh ansible-base-ee-dev
```

The script will:

1. Generate the build context using `ansible-builder`.
2. Build the container image locally.
3. Run a verification step (`ansible --version`) inside the new image.

### 🔐 Optional Red Hat Certified Collections

If `RHN_CS_API_OFFLINE_TOKEN` is available, builds will also install the Red Hat certified `ansible.platform` and `ansible.controller` collections from Automation Hub.

For local builds, both helper scripts will automatically source `.ee-build.env` from the repository root when it exists. That file is intended to point to a second file that exports `RHN_CS_API_OFFLINE_TOKEN`, so the token itself does not need to live in the primary config file. The referenced secrets file can be inside or outside the repository, including a path under your home directory. You can override the config file location with `EE_BUILD_ENV_FILE`.

If the token is not present, the build continues and skips the optional Red Hat collections.

In GitHub Actions, set the repository secret `RHN_CS_API_OFFLINE_TOKEN`. The workflow passes it to Docker as a BuildKit secret so it is not written into the image layers.

### 🏗️ Architecture Support

These images are built for multiple architectures:

* `linux/amd64` (x86_64)
* `linux/arm64` (Apple Silicon, AWS Graviton)

> **Note for ARM64 Users:**
> Some collections (like `azure.azcollection`) may require C extensions that fail to compile on ARM64 locally. In `ansible-base-ee-2.16`, these have been temporarily disabled to allow local builds on Apple Silicon.

## 🤖 CI/CD

This repository uses **GitHub Actions** to automatically build and push images to Quay.io.

* **Trigger**: Pushes to the `main` branch (filtered by directory paths).
* **Registry**: `quay.io/oatakan/ansible-base-ee-*`
* **Tags**:
  * `latest`: The most recent build.
  * `sha-<commit_hash>`: Immutable tag for specific commits.

## 📝 Customization

To add new dependencies:

1. **Galaxy Collections**: Edit `dependencies.galaxy.collections` in `execution-environment.yml`.
2. **Python Packages**: Edit `dependencies.python` in `execution-environment.yml`.
3. **System Packages**: Edit `dependencies.system` in `execution-environment.yml`.
   * Use `[platform:rpm]` for RHEL/CentOS based images.

Example `execution-environment.yml`:

```yaml
dependencies:
  galaxy:
    collections:
      - name: community.general
  python:
    - requests
  system:
    - git [platform:rpm]
```

## 🤝 Contributing

1. Create a feature branch.
2. Make your changes to the relevant `execution-environment.yml`.
3. Test locally using `./build_local.sh`.
4. Submit a Pull Request.
