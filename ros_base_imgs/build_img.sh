#!/bin/bash

# ======================================
# Input arguments
# ======================================

# https://docs.ros.org/ says:
# ros1 noetic ninjemys  - ubuntu 20.04 focal fossa     - long term support (recommended)
# ros2 humble hawksbill - ubuntu 22.04 jammy jellyfish
# ros2 jazzy jalisco    - ubuntu 24.04 noble numbat    - long term support (recommended)
# Associative array
declare -A ros_distros=(
    ["noetic"]="1:20.04"
    ["humble"]="2:22.04"
    ["jazzy"]="2:24.04"
)

# ======================================
# Functions
# ======================================

# Ensures a value is provided for an option that requires an argument.
check_optarg() {
    local flag="${1}"
    local value="${2}"

    if [ -z "${value}" ] || [[ "${value}" == -* ]]; then
        print_banner "Error: Option ${flag} requires a value" 2 "!"
        usage
        exit 1
    fi
}

# Validates that the platform is one of the supported single-platform options for '--load'
check_single_platform() {
    local input="${1}"

    # Disallow multiple platforms
    if [[ "${input}" == *,* ]]; then
        print_banner "Error: Only one platform can be specified when using '--load'\nExample: -P linux/amd64" 2 "!"
        print_supported_platforms 2 2
        exit 1
    fi

    if [ "${input}" != "linux/amd64" ] && [ "${input}" != "linux/arm64" ] && [ "${input}" != "linux/arm/v7" ]; then
        print_banner "Error: Unsupported platform '${input}'" 2 "!"
        print_supported_platforms 2 2
        exit 1
    fi

}

detect_default_platform() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
    # 64-bit x86/Intel/AMD PCs and servers
    x86_64 | amd64)
        echo "linux/amd64"
        ;;

    # All 64-bit ARM (Jetson Nano / Xavier / Orin, Raspberry Pi 5, Apple M-series, etc.)
    aarch64 | arm64)
        echo "linux/arm64"
        ;;

    # 32-bit ARMv7 (legacy Raspberry Pi 2/3 with 32-bit OS)
    armv7l | armv7 | armhf)
        echo "linux/arm/v7"
        ;;

    # Fallback
    *)
        print_banner "Warning: Unknown architecture '${arch}'. Defaulting to 'linux/amd64'" 1 "+"
        echo "linux/amd64"
        ;;
    esac
}

get_ros_distros_str() {
    local initial_str="" # To store the initial unsorted string
    local sorted_str=""  # To store the final sorted string

    # Generate the initial string
    for key in "${!ros_distros[@]}"; do
        value="${ros_distros[${key}]}"
        initial_str+="${value}:${key} "
    done

    # Remove the trailing space
    initial_str="${initial_str% }"

    # Sort the elements and construct the sorted string
    while read -r element; do
        ros_version="${element%%:*}"      # Extract part before the first colon
        remaining="${element#*:}"         # Extract everything after the first colon
        ubuntu_version="${remaining%%:*}" # Extract part before the second colon
        key="${remaining#*:}"             # Extract part after the second colon

        # Append the formatted string to sorted_str
        sorted_str+="${key} (ros${ros_version}, ${ubuntu_version}), "
    done < <(echo "${initial_str}" | tr ' ' '\n' | sort)

    # Remove the trailing comma and space
    echo "${sorted_str%, }"
}

print_banner() {
    local message="${1}"
    local fd="${2:-1}"          # default to 1 (stdout) if not provided
    local border_char="${3:-=}" # default to '=' if not provided

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

print_supported_platforms() {
    local fd="${1:-1}"
    local indent="${2:-0}"
    local space_padding

    # Generate N spaces for indentation
    printf -v space_padding '%*s' "${indent}"

    cat <<EOF >&${fd}
${space_padding}Supported platforms:
${space_padding}linux/amd64  - 64-bit x86_64 (e.g. Intel/AMD PCs and servers)
${space_padding}linux/arm64  - 64-bit ARMv8-A (e.g. Raspberry Pi 4/5, NVIDIA Jetson, Apple Silicon)
${space_padding}linux/arm/v7 - 32-bit ARMv7-A (e.g. Raspberry Pi 2/3 with 32-bit OS)
${space_padding}Default: selected automatically based on the host architecture
${space_padding}If host architecture is not supported, the default is 'linux/amd64'
EOF
}

replace_placeholder_with_file() {
    local pattern="${1}"
    local content_file="${2}"
    local dest_file="${3}"

    # Abort if pattern is not found in the destination file
    if ! grep --quiet --fixed-strings "${pattern}" "${dest_file}"; then
        print_banner "Warning: pattern '${pattern}' not found in '${dest_file}'" 1 "+"
        return 1
    fi

    # Use awk to replace the line containing the pattern with the full content of content_file
    awk -v content_file="${content_file}" -v pattern="${pattern}" '
    index($0, pattern) {
        while ((getline line < content_file) > 0)
            print line;
        close(content_file);
        next;
    }
    { print }
    ' "${dest_file}" >"${dest_file}.tmp" && mv "${dest_file}.tmp" "${dest_file}"
}

# Validates and normalizes the image identifier provided by the user.
# - If only one string is provided (no ':'), ':latest' is appended.
# - If exactly one ':' is found, both parts must be non-empty.
# - Any other case (multiple colons or empty parts) is considered invalid.
set_img_id() {
    local input="${1}"
    local id=""
    local label=""

    # Check if the input string contains a colon.
    # This determines whether the user provided an explicit label (i.e. input is in the form 'name:label')
    #
    # Examples:
    #   input="my_image:dev"      -> enters the 'if' block
    #   input="my_image"          -> skips to 'else', to add ':latest'
    #   input=":dev"              -> enters the 'if' block (but will later fail due to empty 'name')
    #   input="my:image:dev"      -> enters the 'if' block (but will later fail due to multiple colons)
    if [[ "${input}" == *:* ]]; then
        # Split the string into two parts using ':' as separator
        # 'id' will receive the part before the first colon
        # 'label' will receive everything after the first colon
        # Examples:
        #   input="my_image:dev"     -> id="my_image", label="dev"
        #   input=":dev"             -> id="",         label="dev"
        #   input="my_image:"        -> id="my_image", label=""
        #   input="my:image:dev"     -> id="my",       label="image:dev"
        IFS=':' read -r id label <<<"${input}"

        # Ensure neither part is empty.
        if [[ -z "${id}" || -z "${label}" ]]; then
            print_banner "Error: Both parts of the image identifier must be non-empty (format must be 'string:label')" 2 "!"
            exit 1
        fi

        # Ensure there is only one colon
        if [[ "${input}" != "${id}:${label}" ]]; then
            print_banner "Error: Image identifier must contain at most one ':' character" 2 "!"
            exit 1
        fi

        echo "${input}"
    else
        echo "${input}:latest"
    fi
}

usage() {
    echo "Usage: ${script_name} <options>"
    echo
    echo "Options:"
    echo
    echo "  -h            Show this message"
    echo "  -b            Base image. Default: ubuntu:X.Y, matched to the ROS distro"
    echo "  -e            Entrypoint script. Default: entrypoint.sh"
    echo "  -E            Environment script. Default: environment.sh"
    echo "  -i            Image identifier with the format img_id:label (REQUIRED)"
    echo "  -n            Do not use cache when building the Docker image"
    echo "  -N            Image will use NVIDIA runtime. No MESA libraries will be installed in the image"
    echo "  -p            Pull the latest version of the base image"
    echo "  -P platform   Target platform"
    print_supported_platforms 1 16
    echo "  -u            User to run the container (REQUIRED)"
    echo "  -v version    ROS distro (REQUIRED)"
    echo "                Available ROS distros: ${ros_distros_str}"
    echo
    exit 1
}

# =================
# Script execution
# =================

script_name="$(basename "${BASH_SOURCE[0]}")"
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
ros_distros_str=$(get_ros_distros_str)

base_img=""
entrypoint=""
environment=""
img_id=""
user=""
ros_distro=""
platform=""
use_nvidia_support="false"
cache="" # By default cache is used. Cache is used when the variable cache is empty
pull=""

# Process input from user
while getopts 'hb:e:E:i:nNpP:u:v:' option; do
    case "${option}" in
    h)
        usage
        ;;
    b)
        check_optarg "-b" "${OPTARG}"
        base_img="${OPTARG}"
        ;;
    e)
        check_optarg "-e" "${OPTARG}"
        entrypoint="${OPTARG}"
        ;;
    E)
        check_optarg "-E" "${OPTARG}"
        environment="${OPTARG}"
        ;;
    i)
        check_optarg "-i" "${OPTARG}"
        img_id="$(set_img_id "${OPTARG}")"
        ;;
    n)
        cache="--no-cache"
        ;;
    N)
        use_nvidia_support="true"
        # Check if the NVIDIA runtime is available
        if ! docker info | grep -q "Runtimes: nvidia"; then
            print_banner "Warning: NVIDIA runtime not found" 2 "+"
        fi
        ;;
    p)
        pull="--pull"
        ;;
    P)
        check_optarg "-P" "${OPTARG}"
        platform="${OPTARG}"
        check_single_platform "${platform}"
        ;;
    u)
        check_optarg "-u" "${OPTARG}"
        user="${OPTARG}"
        ;;
    v)
        check_optarg "-v" "${OPTARG}"
        ros_distro="${OPTARG}"
        ;;
    ?)
        usage
        ;;
    esac
done

[ -z "${entrypoint}" ] && entrypoint="${base_dir}/entrypoint.sh"

if [ ! -s "${entrypoint}" ]; then
    print_banner "Error: entrypoint script '${entrypoint}' not found" 2 "!"
    exit 1
fi

if [ -z "${img_id}" ]; then
    print_banner "Error: No image id provided" 2 "!"
    usage
fi

[ -z "${platform}" ] && platform="$(detect_default_platform)"

if [ -z "${user}" ]; then
    print_banner "Error: No user provided" 2 "!"
    usage
fi

requested_user="$(echo "${user}" | cut -d: -f1)"

if [ -z "${ros_distro}" ]; then
    print_banner "Error: No ROS distro provided" 2 "!"
    usage
fi

# Check if the ROS distro introduced by the user is valid
if [[ ! -v ros_distros["${ros_distro}"] ]]; then
    print_banner "Error: Invalid ROS distro provided. Allowed ROS distros: ${ros_distros_str}" 2 "!"
    usage
fi

ros_version="$(echo "${ros_distros["${ros_distro}"]}" | cut -d':' -f1)"
ubuntu_version="$(echo "${ros_distros["${ros_distro}"]}" | cut -d':' -f2)"

# If no base image is provided, the script will use the default base image for the ROS distro.
[ -z "${base_img}" ] && base_img="ubuntu:${ubuntu_version}"

[ -z "${environment}" ] && environment="${base_dir}/environment_ros${ros_version}.sh"

if [ ! -s "${environment}" ]; then
    print_banner "Error: environment script '${environment}' not found" 2 "!"
    exit 1
fi

install_core_script="${base_dir}/install_core.sh"
install_ros_template="${base_dir}/install_ros.sh"

# Create the build context to be passed to the building process.
# Create a unique temporary directory using mktemp for the build context and copy the required files there.
# mktemp ensures that the directory does not already exist, preventing name collisions.
context_path="$(mktemp -d /tmp/context_XXXXXXXXXX)"

cp "${install_core_script}" "${context_path}/install_core.sh"
chmod 755 "${context_path}/install_core.sh"

if [ "${use_nvidia_support}" = "false" ]; then
    if [ "${ubuntu_version}" = "20.04" ]; then
        cp "${base_dir}/install_kisak_mesa_packages.sh" "${context_path}/install_mesa_packages.sh"
    # Modern versions of Ubuntu (22.04, 24.04, ...) already have Mesa packages, with support for modern non-nvidia GPUs.
    # If the laptop used, has a super new GPU, a new script to install Mesa packages with custom instructions
    # (including )
    else
        cp "${base_dir}/install_default_mesa_packages.sh" "${context_path}/install_mesa_packages.sh"
    fi
else
    touch "${context_path}/install_mesa_packages.sh" # Empty file, but required for the COPY command, not to fail
fi

chmod 755 "${context_path}/install_mesa_packages.sh"

install_ros_script="${context_path}/install_ros.sh"
cp "${install_ros_template}" "${install_ros_script}"
chmod 755 "${install_ros_script}"

cp "${base_dir}/packages_ros${ros_version}.txt" "${context_path}/ros_packages.txt"

cp "${base_dir}/rosdep_init_update.sh" "${context_path}/rosdep_init_update.sh"
chmod 755 "${context_path}/rosdep_init_update.sh"

cp "${entrypoint}" "${context_path}/entrypoint.sh"
chmod 755 "${context_path}/entrypoint.sh"

cp "${base_dir}/deduplicate_path.sh" "${context_path}/deduplicate_path.sh"
chmod 755 "${context_path}/deduplicate_path.sh"

cp "${base_dir}/environment_root.sh" "${context_path}/environment_root.sh"
chmod 755 "${context_path}/environment_root.sh"

cp "${environment}" "${context_path}/environment.sh"
chmod 755 "${context_path}/environment.sh"

cp "${base_dir}/ros${ros_version}build.sh" "${context_path}/rosbuild.sh"
chmod 755 "${context_path}/rosbuild.sh"

if [ "${ros_version}" = "2" ]; then
    cp "${base_dir}/rosdep_ignored_keys_ros2.yaml" "${context_path}/rosdep_ignored_keys.yaml"

    cp "${base_dir}/colcon_mixin_metadata.sh" "${context_path}/colcon_mixin_metadata.sh"
    chmod 755 "${context_path}/colcon_mixin_metadata.sh"
fi

# Inject the ROS version string into the install_ros script.
if [ "${ros_version}" = "1" ]; then
    ros_version_str="ros"
else
    ros_version_str="ros2"
fi

# Inject the ROS distro into the environment file.
pattern='<ROS_DISTRO>'
sed -i "s/${pattern}/${ros_distro}/g" "${context_path}/environment.sh"

dockerfile="${base_dir}/Dockerfile"

log_dir="/tmp"
log_prefix="build_img_$(echo "${img_id}" | tr ':' '_')_$(date --utc '+%Y-%m-%d_%H-%M-%S')"
docker_log_file="${log_dir}/${log_prefix}.log"
specific_log_file="${log_dir}/${log_prefix}_specific.log"

echo "Building Docker image '${img_id}' with 'ROS${ros_version}-${ros_distro}'"
sleep 2

# Check if the base image has to be found locally or pulled from a remote registry.
# If the base image has to be found locally, we have to set up a local registry to push the image to, since docker
# buildx does not support local images without being pushed to a registry.
if [ "${pull}" = "" ]; then
    echo "Pull not requested"

    if ! docker image inspect "${base_img}" &>/dev/null; then
        echo "Base image '${base_img}' not found locally"
        exit 1
    fi

    echo "Setting up temporary local registry"

    if ! docker image inspect registry:2 &>/dev/null; then
        echo "Pulling 'registry:2' image"
        docker pull registry:2 || exit 1
    elif docker container inspect temp_registry &>/dev/null; then
        docker rm -f temp_registry
    fi

    # Launch registry in temp_registry_net network
    docker run -d --rm -p 5000:5000 --name temp_registry registry:2 || exit 1

    echo "Waiting for local registry to be available"
    local_registry_ready=0

    for i in {1..10}; do
        if curl -s http://localhost:5000/v2/ &>/dev/null; then
            echo "Local registry is ready"
            local_registry_ready=1
            break
        fi

        printf "."
        sleep 1
    done

    printf "\n"

    if [ "${local_registry_ready}" -eq 0 ]; then
        echo "Error: Local registry did not become available after 10 seconds"
        # rm is not needed here, as the container will be removed automatically.
        docker stop temp_registry
        exit 1
    fi

    original_base_img="${base_img}"
    local_push_base_img="localhost:5000/${original_base_img}"

    echo "Tagging base image '${original_base_img}' to '${local_push_base_img}'"
    docker image tag "${original_base_img}" "${local_push_base_img}"
    docker push "${local_push_base_img}" || exit 1

    bridge_gw=$(docker network inspect bridge -f '{{ ( index .IPAM.Config 0 ).Gateway }}')
    build_base_img="${bridge_gw}:5000/${original_base_img}"

    echo "Build base image set to '${build_base_img}'"
else
    # If pull is requested, use the base image as is.
    build_base_img="${base_img}"
fi

# BuildKit is the default builder for users on Docker Desktop and Docker Engine v23.0 and later.
# However, just in case BuildKit is not the default builder in the machine that runs this script, we
# set the DOCKER_BUILDKIT environment variable to 1 to enable BuildKit.
DOCKER_BUILDKIT=1 docker buildx build \
    --builder docker_multiarch_builder \
    --platform "${platform}" \
    --file "${dockerfile}" \
    ${cache} ${pull} \
    --progress=plain \
    --build-arg base_img="${build_base_img}" \
    --build-arg REQUESTED_USER="${requested_user}" \
    --build-arg ROS_DISTRO="${ros_distro}" \
    --build-arg ROS_VERSION="${ros_version}" \
    --build-arg USE_NVIDIA_SUPPORT="${use_nvidia_support}" \
    --label org.opencontainers.image.title="ROS${ros_version} development Docker image" \
    --label org.opencontainers.image.description="A Docker image for ROS${ros_version} development and testing" \
    --label org.opencontainers.image.authors="$(id -u --name)" \
    --label org.opencontainers.image.created="$(date --utc '+%Y-%m-%d-%H-%M-%S')" \
    --tag "${img_id}" \
    --load \
    "${context_path}" 2>&1 | tee "${docker_log_file}"

# Filter the complete log to extract the custom lines with the pattern [timestamp] message.
pattern='\[[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\]'
sed -E -n "s/.*(${pattern})/\1/p" "${docker_log_file}" >"${specific_log_file}"
sed -E "/${pattern}/d" "${docker_log_file}" >"${docker_log_file}.tmp"
mv "${docker_log_file}.tmp" "${docker_log_file}"

# Remove the context path after the images has been created.
if [ -d "${context_path}" ]; then
    echo "Removing context path '${context_path}'"
    rm -rf "${context_path}"
fi

if [ "${pull}" = "" ]; then
    echo "Stopping and removing temporary local registry"
    # rm is not needed here, as the container will be removed automatically.
    docker stop temp_registry &>/dev/null

    echo "Removing image tag '${local_push_base_img}'"
    docker image rm "${local_push_base_img}"
fi

echo "Docker build log file:   '${docker_log_file}'"
if [ -s "${specific_log_file}" ]; then
    echo -e "Specific build log file: '${specific_log_file}'\n"
else
    rm "${specific_log_file}"
fi
