#!/usr/bin/env bash

log() {
    local message="${1}"
    local fd="${2:-1}" # default to 1 (stdout) if not provided

    # Validate that fd is either 1 (stdout) or 2 (stderr)
    if [[ "${fd}" != "1" && "${fd}" != "2" ]]; then
        fd=1
    fi

    printf "[%s] %s\n" "$(date --utc '+%Y-%m-%d_%H-%M-%S')" "${message}" >&"${fd}"
}

ROS_DISTRO="${1}"
IMG_USER="${2}"
SRC_ROSDEP_IGNORED_KEY_FILE="${3}"

[ -z "${ROS_DISTRO}" ] && {
    log "Error: ROS_DISTRO is not set" 2
    exit 1
}

[ -z "${IMG_USER}" ] && {
    log "Error: IMG_USER is not set" 2
    exit 1
}

img_user_entry="$(getent passwd "${IMG_USER}")"

[ -z "${img_user_entry}" ] && {
    log "Error: User '${IMG_USER}' does not exist" 2
    exit 1
}

# This script is run by root when building the Docker image.
[ "$(id --user)" -ne 0 ] && {
    log "Error: root user must be active to run the script '$(basename "${BASH_SOURCE[0]}")'" 2
    exit 1
}

rosdep_root_dir="/etc/ros/rosdep"
rosdep_sources_dir="${rosdep_root_dir}/sources.list.d"

if [ ! -d "${rosdep_sources_dir}" ]; then
    log "Creating path ${rosdep_sources_dir}"
    mkdir --verbose "${rosdep_sources_dir}"
elif [ -e "${rosdep_sources_dir}/20-default.list" ]; then
    log "File '${rosdep_sources_dir}/20-default.list' already exists, removing it"
    rm -f "${rosdep_sources_dir}/20-default.list"
fi

# Check if there are keys to ignore for rosdep.
if [ -s "${SRC_ROSDEP_IGNORED_KEY_FILE}" ]; then
    dst_rosdep_ignored_key_file="${rosdep_root_dir}/rosdep_ignored_keys.yaml"
    rosdep_ignored_keys_list_file="${rosdep_sources_dir}/00-rosdep-ignored-key-file-list.list"

    log "rosdep ignored keys provided in the file "${SRC_ROSDEP_IGNORED_KEY_FILE}""

    # Check if there is no file with exclusions for rosdep yet.
    if [ ! -s "${dst_rosdep_ignored_key_file}" ]; then
        log "Copying file '"${SRC_ROSDEP_IGNORED_KEY_FILE}"' file to '${dst_rosdep_ignored_key_file}'"
        cp "${SRC_ROSDEP_IGNORED_KEY_FILE}" "${dst_rosdep_ignored_key_file}"
    # Check if the rosdep exclusions file present in the image and the provided one are different.
    elif ! cmp --silent "${SRC_ROSDEP_IGNORED_KEY_FILE}" "${dst_rosdep_ignored_key_file}"; then
        bak_file="${dst_rosdep_ignored_key_file}.bak_$(date +%Y%m%d_%H%M%S)"
        log "File '${dst_rosdep_ignored_key_file}' already exists, backing it up to file '${bak_file}'"
        mv "${dst_rosdep_ignored_key_file}" "${bak_file}"
        log "Copying file '"${SRC_ROSDEP_IGNORED_KEY_FILE}"' file to '${dst_rosdep_ignored_key_file}'"
        cp "${SRC_ROSDEP_IGNORED_KEY_FILE}" "${dst_rosdep_ignored_key_file}"
    else
        log "File with rosdep ignored keys already present in the image"
    fi

    # Check if the rosdep ignored keys file is already included in the list file.
    if ! grep -E "yaml file://${dst_rosdep_ignored_key_file}" "${rosdep_ignored_keys_list_file}"; then
        log "Adding file '${dst_rosdep_ignored_key_file}' to the list file '${rosdep_ignored_keys_list_file}'"
        echo "yaml file://${dst_rosdep_ignored_key_file}" >>"${rosdep_ignored_keys_list_file}"
    else
        log "File '${dst_rosdep_ignored_key_file}' already present in the file '${rosdep_ignored_keys_list_file}'"
    fi
else
    log "No rosdep exclusions to consider"
fi

log "Executing rosdep init"

if ! rosdep init; then
    log "Error: rosdep init failed" 2
    exit 1
fi

# If the command 'rosdep update' is run as root, the rosdep database is located at /root/.ros/rosdep.
# Ref: rosdep --help
items=(meta.cache sources.cache)
# Path where the rosdep databases are located when the command rosdep update is executed as root.
rosdep_src_dir="/root/.ros/rosdep"

# Check if the databases already exists in the proper path.
for item in "${items[@]}"; do
    src_item="${rosdep_src_dir}/${item}"

    if [ -e "${src_item}" ]; then
        bak_item="${src_item}.bak_$(date --utc '+%Y-%m-%d_%H-%M-%S')"
        log "Baking up item '${bak_item}'"
        mv "${src_item}" "${bak_item}"

        log "Removing item '${src_item}'"
        rm -rf "${src_item}"
    fi
done

log "Executing rosdep update as root. Ignore the warning about running as root"
log "rosdep database ownership will be fixed later"
rosdep update --rosdistro "${ROS_DISTRO}"

log "Installing dependencies for packages in the path /opt/ros/${ROS_DISTRO}/share/"
# Update cache to ensure the latest package information is available.
apt-get update
rosdep install -y --rosdistro "${ROS_DISTRO}" --from-paths "/opt/ros/${ROS_DISTRO}/share/" --ignore-src

# Move the rosdep databases to the user home directory, if the IMG_USER is not root.
if [ "${IMG_USER}" != "root" ]; then
    rosdep_dst_dir="${img_user_home}/.ros/rosdep"

    if [ ! -d "${rosdep_dst_dir}" ]; then
        log "Directory '${rosdep_dst_dir}' does not exist, creating it"
        mkdir --parent "${rosdep_dst_dir}"

        # Copy the items from the source directory to the destination directory.
        for item in "${items[@]}"; do
            src_item="${rosdep_src_dir}/${item}"
            dst_item="${rosdep_dst_dir}/${item}"
            log "Moving item '${src_item}' into '${dst_item}'"
            mv "${src_item}" "${dst_item}"
        done
    else
        for item in "${items[@]}"; do
            dst_item="${rosdep_dst_dir}/${item}"

            if [ -e "${dst_item}" ]; then
                bak_item="${dst_item}.bak_$(date --utc '+%Y-%m-%d_%H-%M-%S')"
                log "Baking up item '${bak_item}'"
                mv "${dst_item}" "${bak_item}"

                log "Removing item '${dst_item}'"
                rm -rf "${dst_item}"
            fi

            src_item="${rosdep_src_dir}/${item}"
            log "Moving item '${src_item}' into '${dst_item}'"
            mv "${src_item}" "${dst_item}"
        done
    fi
fi
