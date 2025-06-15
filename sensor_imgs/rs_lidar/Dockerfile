# syntax=docker/dockerfile:1

# No default base_img is provided to ensure the build process fails if no base_img is specified.
# The warning 'InvalidDefaultArgInFrom: Default value for ARG ${base_img} results in empty or
# invalid base image name' can be safely ignored, as this behavior is intentional.
ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION}

# The following labels adhere to the OCI Image Specification for standardized metadata.
# Reference: https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL org.opencontainers.image.title="RS Lidar Docker Image" \
    org.opencontainers.image.description="A Docker image to launch RS Lidars" \
    org.opencontainers.image.authors="anon"

ARG ROS_DISTRO=humble
ARG ROS_VERSION=2

ENV IMG_USER="sensor" \
    IMG_USER_HOME="/home/sensor" \
    IMG_USER_WORKSPACE="/home/sensor/workspace" \
    ROS_DISTRO="${ROS_DISTRO}" \
    ROS_VERSION="${ROS_VERSION}" \
    DEBIAN_FRONTEND="noninteractive"

USER root
WORKDIR /

SHELL ["/bin/bash", "-c"]

RUN --mount=type=bind,source=.,target=/tmp/context <<'EOF'
log() { echo "[$(date --utc '+%Y-%m-%d_%H-%M-%S')]" "$@"; }

[ -z "${ROS_DISTRO}" ] && {
    log "Error: No ROS_DISTRO provided" 2
    exit 1
}

[ -z "${ROS_VERSION}" ] && {
    log "Error: No ROS_VERSION provided" 2
    exit 1
}

if [[ ! "${ROS_VERSION}" =~ ^(1|2)$ ]]; then
    log "Error: Invalid ROS version '${ROS_VERSION}'. Must be 1 or 2." 2
    exit 1
fi

log "Installing system packages"
# Update the package list and upgrade all packages to their latest versions.
apt-get update

# Install the apt-utils package first, to avoid warnings when installing packages if this package
# is not installed previously.
apt-get install --yes --no-install-recommends apt-utils

# Upgrade the system to ensure all packages are up to date, now that apt-utils is installed.
apt-get apt-get dist-upgrade --yes

# Install essential system packages.
apt-get install --yes --no-install-recommends build-essential ca-certificates cmake cmake-data curl gcc git gpg nano openssh-client sudo vim

log "Configuring UTC time"
# Configure UTC time.
echo "Etc/UTC" >/etc/timezone
ln --symbolic --force --no-dereference "/usr/share/zoneinfo/etc/utc" /etc/localtime
apt-get install --yes --no-install-recommends tzdata

log "Configuring locales to en_US.UTF-8"
# Install the locales package to support UTF-8 encoding.
apt-get install --yes --no-install-recommends locales
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen en_US.UTF-8

# Create a new user with the specified username and home directory.
useradd --create-home --home-dir "${IMG_USER_HOME}" --shell /bin/bash "${IMG_USER}"
img_entry="$(getent passwd "${IMG_USER}")"
img_user_id="$(echo "${img_entry}" | cut -d: -f3)"
img_user_pri_group_id="$(echo "${img_entry}" | cut -d: -f4)"
img_user_pri_group="$(getent group "${img_user_pri_group_id}" | cut -d: -f1)"
log "Created user '${IMG_USER}' (UID '${img_user_id}') with primary group '${img_user_pri_group}' (GID '${img_user_pri_group_id}') and home directory '${IMG_USER_HOME}'"

log "Adding user '${IMG_USER}' to the 'dialout', 'sudo', and 'video' groups"
usermod --append --groups dialout "${IMG_USER}"
usermod --append --groups sudo "${IMG_USER}"
usermod --append --groups video "${IMG_USER}"
password="${IMG_USER}"
echo "${IMG_USER}:${password}" | chpasswd

log "Creating directories .config, .local/bin, .local/lib, and .local/share under the path '${IMG_USER_HOME}'"
install --directory --mode 755 --owner sensor --group sensor /home/sensor/.config
install --directory --mode 755 --owner sensor --group sensor /home/sensor/.local/bin
install --directory --mode 755 --owner sensor --group sensor /home/sensor/.local/lib
install --directory --mode 755 --owner sensor --group sensor /home/sensor/.local/share

log "Installing ROS${ROS_VERSION}-${ROS_DISTRO}"
ros_versions_str=("ros" "ros2")
ros_version_str="${ros_versions_str[$((ROS_VERSION - 1))]}"
gpg_dir="/etc/apt/keyrings"
mkdir --verbose --parent "${gpg_dir}"
gpg_file="${gpg_dir}/ros.gpg"
curl --fail --silent --show-error --location https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | gpg --dearmor --output "${gpg_file}"
chmod 644 "${gpg_file}"
version_codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
url="http://packages.ros.org/${ros_version_str}/ubuntu"
ros_deb_line="deb [arch=$(dpkg --print-architecture) signed-by=${gpg_file}] ${url} ${version_codename} main"
ros_list_file="/etc/apt/sources.list.d/ros.list"
echo "${ros_deb_line}" | tee "${ros_list_file}" >/dev/null
apt-get update

packages=(ros-${ROS_DISTRO}-ros-core "${ros_version_str}-apt-source" python3-rosdep)

if [ "${ROS_VERSION}" -eq 1 ]; then
    packages+=(python3-catkin-tools)
else
    packages+=(python3-colcon-common-extensions python3-colcon-mixin python3-colcon-metadata)
fi

apt-get install --yes --no-install-recommends "${packages[@]}"

rm -rf "${ros_list_file}"
rm -rf "${gpg_file}"

log "Initializing rosdep"
rosdep_root_dir="/etc/ros/rosdep"
rosdep_sources_dir="${rosdep_root_dir}/sources.list.d"
mkdir --verbose --parent "${rosdep_sources_dir}"
dst_rosdep_ignored_key_file="${rosdep_root_dir}/rosdep_ignored_keys.yaml"
rosdep_ignored_keys_list_file="${rosdep_sources_dir}/00-rosdep-ignored-key-file-list.list"

# Ignore non-open-source DDS.
cat > "${dst_rosdep_ignored_key_file}" <<'EOL'
# Ref: https://github.com/ros-infrastructure/rosdep/issues/649
# Locally ignore rosdep keys using empty list of packages: https://github.com/ros-infrastructure/rosdep/issues/649
# Skip connextdds and gurumdds middleware packages.

rmw_connextdds: {ubuntu: []}
rmw_connextdds_common: {ubuntu: []}
rti-connext-dds-cmake-module: {ubuntu: []}
rmw_gurumdds_cpp: {ubuntu: []}
gurumdds_cmake_module: {ubuntu: []}
EOL

echo "yaml file://${dst_rosdep_ignored_key_file}" >>"${rosdep_ignored_keys_list_file}"

if ! rosdep init; then
    log "Error: rosdep init failed" 2
    exit 1
fi

log "Executing rosdep update as root. Ignore the warning about running as root"
log "rosdep database ownership will be fixed later"
rosdep update --rosdistro "${ROS_DISTRO}"

# Install dependencies for the rslidar_sdk. Next rosdep is used to install dependencies for the
# packages in the paths '/opt/ros/${ROS_DISTRO}/share/' and '${IMG_USER_WORKSPACE}/src'.
log "Installing dependencies for the rslidar_sdk package"
apt-get install -y --no-install-recommends libpcap-dev libeigen3-dev libyaml-cpp-dev
mkdir --verbose --parent "${IMG_USER_WORKSPACE}/src"
log "Cloning the rslidar_sdk repository into '${IMG_USER_WORKSPACE}/src/rslidar_sdk'"
cd "${IMG_USER_WORKSPACE}/src"
git clone https://github.com/RoboSense-LiDAR/rslidar_sdk.git
cd rslidar_sdk
git submodule init
git submodule update

# According to the rslidar_sdk documentation
# (https://github.com/RoboSense-LiDAR/rslidar_sdk/blob/main/README.md), the package rslidar_msg
# is required for ROS 2, but not for ROS 1.
if [ "${ROS_VERSION}" -eq 2 ]; then
    log "Cloning the rslidar_msg repository into '${IMG_USER_WORKSPACE}/src/rslidar_msg'"
    cd "${IMG_USER_WORKSPACE}/src"
    # We clone the repo from RobotnikAutomation, which is a fork of the original rslidar_msg
    # repository, since it contains an enhancement that allows the package to be built and run with
    # both ROS 1 and ROS 2.
    # https://github.com/RoboSense-LiDAR/rslidar_msg/pull/3
    # Clean and merge ros1 and ros2 cmakelists and package.
    # This pull request includes significant updates to support both ROS and ROS2 environments in the
    # rslidar_msg project. The most important changes include modifications to the CMakeLists.txt and
    # package.xml files to conditionally handle dependencies and configurations for ROS and ROS2, as
    # well as cleanup of redundant files.
    git clone https://github.com/RobotnikAutomation/rslidar_msg.git
fi

# Modernize CMake conditionals in CMakeLists.txt files for the rslidar_sdk.
# 1) if(${VAR} …)  ⇒  if(VAR …)
#    - CMake’s modern style uses the variable name directly (VAR)
#      instead of the expanded form (${VAR}).
#    - Leaving ${VAR} inside an if() confuses CMake’s variable-tracking and
#      triggers “Manually-specified variables were not used” warnings.
#    - We capture the variable name (group 1) and *everything* that follows
#      until the closing parenthesis (group 2), then rebuild the line.
#
# 2) endif( … )  ⇒  endif()
#    - Arguments to endif() are deprecated/ignored; keeping them is noisy and
#      error-prone if the condition later changes.
#    - We therefore strip anything between the parentheses, leaving a clean
#      canonical endif().

log "Modernizing CMake conditionals in the CMakeLists.txt file for the rslidar_sdk package"
sed -i -E -e 's/if\([[:space:]]*\$\{([A-Za-z_][A-Za-z0-9_]*)\}([[:space:]]*[^)]*)?\)/if(\1\2)/g' \
          -e 's/endif\([[:space:]]*[^)]*[[:space:]]*\)/endif()/g' \
          "${IMG_USER_WORKSPACE}/src/rslidar_sdk/CMakeLists.txt"

# Update default POINT_TYPE in the CMakeLists.txt file for the rslidar_sdk package.
# set(POINT_TYPE XYZI)  ->  set(POINT_TYPE XYZIRT)
log "Updating POINT_TYPE from XYZI to XYZIRT in the CMakeLists.txt file for the rslidar_sdk package"
sed -i -E \
  's/^([[:space:]]*set\([[:space:]]*POINT_TYPE[[:space:]]+)XYZI([[:space:]]*\))/\1XYZIRT\2/' \
  ${IMG_USER_WORKSPACE}/src/rslidar_sdk/CMakeLists.txt

log "Installing dependencies with rosdep for packages in the paths '/opt/ros/${ROS_DISTRO}/share/' and '${IMG_USER_WORKSPACE}/src'"
# Avoid rosdep from installing recommended and suggested packages.
echo 'APT::Install-Recommends "0";' >  /etc/apt/apt.conf.d/99norecommends
echo 'APT::Install-Suggests   "0";' >> /etc/apt/apt.conf.d/99norecommends
paths=("/opt/ros/${ROS_DISTRO}/share/" "${IMG_USER_WORKSPACE}/src")
rosdep install -y --rosdistro "${ROS_DISTRO}" --from-paths "${paths[@]}" --ignore-src

rosdep_src_dir="/root/.ros/rosdep"
rosdep_dst_dir="${IMG_USER_HOME}/.ros/rosdep"
mkdir --verbose --parent "${rosdep_dst_dir}"
log "Moving rosdep files from '${rosdep_src_dir}' to '${rosdep_dst_dir}'"
mv --verbose "${rosdep_src_dir}/meta.cache" "${rosdep_dst_dir}/meta.cache"
mv --verbose "${rosdep_src_dir}/sources.cache" "${rosdep_dst_dir}/sources.cache"

if [ "${ROS_VERSION}" -eq 2 ]; then
    log "Installing colcon mixin and metadata for ROS 2"
    colcon mixin add default https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml
    colcon mixin update default
    colcon metadata add default https://raw.githubusercontent.com/colcon/colcon-metadata-repository/master/index.yaml
    colcon metadata update default

    colcon_src_dir="/root/.colcon"
    colcon_dst_dir="${IMG_USER_HOME}/.colcon"
    mkdir --verbose --parent "${colcon_dst_dir}"
    log "Moving colcon files from '${colcon_src_dir}' to '${colcon_dst_dir}'"
    mv --verbose "${colcon_src_dir}/metadata" "${colcon_dst_dir}/metadata"
    mv --verbose "${colcon_src_dir}/metadata_repositories.yaml" "${colcon_dst_dir}/metadata_repositories.yaml"
    mv --verbose "${colcon_src_dir}/mixin" "${colcon_dst_dir}/mixin"
    mv --verbose "${colcon_src_dir}/mixin_repositories.yaml" "${colcon_dst_dir}/mixin_repositories.yaml"
fi

entrypoint_file="/usr/local/bin/entrypoint.sh"
log "Installing file '${entrypoint_file}'"
cat <<'EOS' > "${entrypoint_file}"
#!/bin/bash

set -e

[ -s "${IMG_USER_WORKSPACE}/install/setup.bash" ] && . "${IMG_USER_WORKSPACE}/install/setup.bash"

exec "$@"
EOS

chmod 775 "${entrypoint_file}"

log "Installing launch script '${IMG_USER_HOME}/launch.sh'"
cat <<'EOS' > "${IMG_USER_HOME}/launch.sh"
#!/bin/bash

config_path="${HOME}/config.yaml"

if [ -s "${config_path}" ]; then
    if [ "${ROS_VERSION}" = "1" ]; then
        setsid roscore
        sleep 1
        rosrun rslidar_sdk rslidar_sdk_node _config_path:="${config_path}"
    else
        ros2 run rslidar_sdk rslidar_sdk_node --ros-args -p config_path:="${config_path}"
    fi
else
    echo "No configuration file found at '${config_path}'."
fi
EOS

chmod 775 "${IMG_USER_HOME}/launch.sh"

log "Setting ownership of path '${IMG_USER_HOME}' to user '${IMG_USER}' (UID '${img_user_id}') and primary group '${img_user_pri_group}' (GID '${img_user_pri_group_id}')"
chown --recursive "${IMG_USER}":"${img_user_pri_group}" "${IMG_USER_HOME}"

log "Removing installation residues from apt cache"
apt-get autoclean
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/* &>/dev/null
EOF

USER "${IMG_USER}"
WORKDIR "${IMG_USER_HOME}"
# Different colcon build commands are used for the rslidar_msg and rslidar_sdk packages, so
# we can pass the option ENABLE_TRANSFORM=ON to the rslidar_sdk package only, avoiding a warning
# about 'Option ENABLE_TRANSFORM is not used' that occurs when only one colcon build command is
# used, since this option is passed to every package to compile, and the package rslidar_msg does
# not use this option.
RUN <<'EOF'
source /opt/ros/${ROS_DISTRO}/setup.bash
cd "${IMG_USER_WORKSPACE}"

cxx_flags="-Wall -Wextra -Wpedantic -Wnon-virtual-dtor -Woverloaded-virtual -Wnull-dereference -Wunused-parameter"

if [ "${ROS_VERSION}" -eq 1 ]; then
    catkin_make \
        --pkg rslidar_sdk \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="${cxx_flags}" \
        -DENABLE_TRANSFORM=ON

   catkin_make install
else
    colcon build \
        --packages-select rslidar_msg \
        --symlink-install --merge-install --mixin release \
        --cmake-args -DCMAKE_CXX_FLAGS="${cxx_flags}"

    colcon build \
        --packages-select rslidar_sdk \
        --packages-skip-build-finished \
        --symlink-install \
        --merge-install \
        --mixin release \
        --cmake-args -DCMAKE_CXX_FLAGS="${cxx_flags}" \
                     -DENABLE_TRANSFORM=ON
fi
EOF

# Configure timezone and localization settings.
# - TZ: Set the timezone to UTC to ensure consistent time handling across environments.
# - LC_ALL, LANG, LANGUAGE: Configure localization to US English and UTF-8 encoding, which helps
#   avoiding issues with character encoding and ensures compatibility with most tools and libraries.
ENV TZ="Etc/UTC" \
    LC_ALL="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    ROS_HOME="${IMG_USER_HOME}/.ros" \
    ROS_LOG_DIR="${IMG_USER_HOME}/.ros/logs" \
    ROS_TEST_RESULTS_DIR="${IMG_USER_HOME}/.ros/tests" \
    ROS_CONFIG_HOME="${IMG_USER_HOME}/.config/ros.org"
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-c", "${IMG_USER_HOME}/launch.sh"]