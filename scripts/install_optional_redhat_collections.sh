#!/usr/bin/env bash
set -euo pipefail

secret_path="${RHN_CS_API_OFFLINE_TOKEN_FILE:-/run/secrets/rhn_cs_api_offline_token}"

if [[ -n "${RHN_CS_API_OFFLINE_TOKEN:-}" ]]; then
    token="${RHN_CS_API_OFFLINE_TOKEN}"
elif [[ -s "${secret_path}" ]]; then
    token="$(<"${secret_path}")"
else
    echo "Skipping Red Hat certified collections: RHN_CS_API_OFFLINE_TOKEN not provided."
    exit 0
fi

tmp_requirements="$(mktemp)"
cleanup() {
    rm -f "${tmp_requirements}"
}
trap cleanup EXIT

cat > "${tmp_requirements}" <<'EOF'
---
collections:
  - name: ansible.platform
  - name: ansible.controller
EOF

export ANSIBLE_GALAXY_SERVER_LIST="automation_hub,release_galaxy"
export ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_URL="${ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_URL:-https://console.redhat.com/api/automation-hub/content/published/}"
export ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_AUTH_URL="${ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_AUTH_URL:-https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token}"
export ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_CLIENT_ID="${ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_CLIENT_ID:-cloud-services}"
export ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN="${token}"
export ANSIBLE_GALAXY_SERVER_RELEASE_GALAXY_URL="${ANSIBLE_GALAXY_SERVER_RELEASE_GALAXY_URL:-https://galaxy.ansible.com/}"

echo "Installing optional Red Hat certified collections from Automation Hub..."
ANSIBLE_GALAXY_DISABLE_GPG_VERIFY=1 ansible-galaxy collection install -r "${tmp_requirements}" --collections-path "/usr/share/ansible/collections"