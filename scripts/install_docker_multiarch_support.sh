#!/bin/bash

#set -euo pipefail
set -eo pipefail

print_banner() {
    local message="${1}"
    local fd="${2:-1}"          # default to 1 (stdout) if not provided
    local border_char="${3:--}" # default to '=' if not provided

    # Validate that fd is either 1 (stdout) or 2 (stderr)
    if [[ "${fd}" != "1" && "${fd}" != "2" ]]; then
        fd=1
    fi

    local line=" ${message} "
    local len=${#line}

    printf "%s\n" "$(printf "%${len}s" | tr ' ' "${border_char}")" >&"${fd}"
    printf "%s\n" "${line}" >&"${fd}"
    printf "%s\n" "$(printf "%${len}s" | tr ' ' "${border_char}")" >&"${fd}"
}

# Check if a command exists
if ! command -v docker &>/dev/null; then
    print_banner "Error: Required command 'docker' is not installed or not in PATH." 2 "!"
    exit 1
fi

if ! docker buildx version &>/dev/null; then
    print_banner "Error: Docker Buildx is not available. Make sure it's enabled (Docker version >= 19.03)." 2 "!"
    exit 1
fi

# Register QEMU for cross-platform builds
print_banner "Registering QEMU with user-static binaries"
docker run --rm --privileged multiarch/qemu-user-static --reset --persistent yes

# Configure Buildx builder
builder="docker_multiarch_builder"
print_banner "Checking if '${builder}' already exists"

if docker buildx ls | grep --quiet "^${builder}"; then
    print_banner "Removing existing builder '${builder}'"
    docker buildx rm "${builder}" &>/dev/null
fi

bridge_gw=$(docker network inspect bridge -f '{{ ( index .IPAM.Config 0 ).Gateway }}')

if [[ -z "${bridge_gw}" ]]; then
    print_banner "Error: Failed to retrieve the bridge network gateway." 2 "!"
    exit 1
fi

print_banner "Detected bridge network gateway: ${bridge_gw}"

if [ -n "${DOCKER_CONFIG}" ]; then
    mkdir -p "${DOCKER_CONFIG}"
    config_file="${DOCKER_CONFIG}/${builder}.toml"
else
    mkdir -p "${HOME}/.docker"
    config_file="${HOME}/.docker/${builder}.toml"
fi

print_banner "Creating configuration file for builder '${builder}' at '${config_file}'"

cat >"${config_file}" <<EOF
[registry."${bridge_gw}:5000"]
  http     = true
  insecure = true
EOF

print_banner "Creating builder '${builder}'"
docker buildx create --name "${builder}" --driver docker-container \
    --config "${config_file}" \
    --use &>/dev/null

# Bootstrap the builder
print_banner "Bootstrapping the builder '${builder}'"
docker buildx inspect --bootstrap

print_banner "Docker multi-architecture support is set up successfully"
