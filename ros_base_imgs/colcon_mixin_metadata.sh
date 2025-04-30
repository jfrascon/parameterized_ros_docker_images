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

IMG_USER="${1}"

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

log "Executing colcon mixin and colcon metadata as root"
echo "colcon databases ownership will be fixed later "

items=(metadata metadata_repositories.yaml mixin mixin_repositories.yaml)
colcon_src_dir="/root/.colcon"

for item in "${items[@]}"; do
    src_item="${colcon_src_dir}/${item}"

    if [ -e "${src_item}" ]; then
        bak_item="${src_item}.bak_$(date --utc '+%Y-%m-%d_%H-%M-%S')"
        log "Baking up item '${bak_item}'"
        mv "${src_item}" "${bak_item}"

        log "Removing item '${src_item}'"
        rm -rf "${src_item}"
    fi
done

# Download the colcon mixin and metadata repositories.
log "Adding colcon mixin repository and updating it"
colcon mixin add default https://raw.githubusercontent.com/colcon/colcon-mixin-repository/master/index.yaml
colcon mixin update default

log "Adding colcon metadata repository and updating it"
colcon metadata add default https://raw.githubusercontent.com/colcon/colcon-metadata-repository/master/index.yaml
colcon metadata update default

img_user_home="$(getent passwd "${IMG_USER}" | cut -d: -f6)"
colcon_dst_dir="${img_user_home}/.colcon"

if [ ! -d "${colcon_dst_dir}" ]; then
    log "Directory '${colcon_dst_dir}' does not exist, creating it"
    mkdir -p "${colcon_dst_dir}"

    # Copy the items from the source directory to the destination directory.
    for item in "${items[@]}"; do
        src_item="${colcon_src_dir}/${item}"
        dst_item="${colcon_dst_dir}/${item}"
        log "Moving item '${src_item}' into '${dst_item}'"
        mv "${src_item}" "${dst_item}"
    done
else
    for item in "${items[@]}"; do
        dst_item="${colcon_dst_dir}/${item}"

        if [ -e "${dst_item}" ]; then
            bak_item="${dst_item}.bak_$(date --utc '+%Y-%m-%d_%H-%M-%S')"
            log "Baking up item '${bak_item}'"
            mv "${dst_item}" "${bak_item}"

            log "Removing item '${dst_item}'"
            rm -rf "${dst_item}"
        fi

        src_item="${colcon_src_dir}/${item}"
        log "Moving item '${src_item}' into '${dst_item}'"
        mv "${src_item}" "${dst_item}"
    done
fi
