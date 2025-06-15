#!/bin/bash

print_banner() {
    local message="${1}"
    local border_char="${2:-=}" # default to '=' if not provided

    local padding=" "
    local line=" ${message} "
    local len=${#line}

    printf "%s\n" "$(printf "%${len}s" | tr ' ' "${border_char}")"
    printf "%s\n" "${line}"
    printf "%s\n" "$(printf "%${len}s" | tr ' ' "${border_char}")"
}

print_banner " Installing Docker "

sudo apt-get update --yes
sudo apt-get dist-upgrade --yes
sudo apt-get install --yes --quiet --no-install-recommends curl gpg

gpg_dir="/etc/apt/keyrings"
gpg_file="${gpg_dir}/docker.gpg"

if [ ! -d "${gpg_dir}" ]; then
    sudo \mkdir -p "${gpg_dir}"
elif [ -f "${gpg_file}" ]; then
    sudo \rm -f "${gpg_file}"
fi

# Download and install the Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
    gpg --dearmor --output - |
    sudo tee "${gpg_file}" >/dev/null

# Set correct permissions
sudo chmod 644 "${gpg_file}"
sudo chown root:root "${gpg_file}"

# Get relevant environment variables, included VERSION_CODENAME.
. /etc/os-release

url="https://download.docker.com/linux/ubuntu"
deb_pattern="^deb.*${url}[[:space:]]+${VERSION_CODENAME}[[:space:]]+stable"
deb_line="deb [arch=$(dpkg --print-architecture) signed-by=${gpg_file}] ${url} ${VERSION_CODENAME} stable"
list_file="/etc/apt/sources.list.d/docker.list"

# Search for any file containing a matching Docker deb line and remove the line or the file, depending on the file where
# the line is found.
matched_files="$(grep -lE "${deb_pattern}" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null)"

for matched_file in ${matched_files}; do
    if [ "${matched_file}" = "/etc/apt/sources.list" ]; then
        print_banner "Docker deb line found in the file '${matched_file}', removing matching lines..."
        # Remove the line from the sources.list file.
        sudo sed -i -E "\#${deb_pattern}#d" "${matched_file}"
    else
        # Remove the file from sources.list.d.
        print_banner "Docker deb line found in the file '${matched_file}', removing file..."
        sudo rm -f "${matched_file}"
    fi
done

# Configure Docker repository
print_banner "Adding custom Docker deb line to file '${list_file}'..."
echo "${deb_line}" | sudo tee "${list_file}" >/dev/null

# Install Docker packages
sudo apt-get update --yes
sudo apt-get install --yes --quiet --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Manage Docker group and permissions
if ! getent group docker >/dev/null; then
    sudo groupadd docker
fi

sudo usermod -aG docker "${USER}"

# Clean up unused packages
sudo apt-get autoremove --yes

# On Debian and Ubuntu, the Docker service is configured to start on boot by default.
# To automatically start Docker and Containerd on boot for other distros, use the commands below:
# sudo systemctl enable docker.service
# sudo systemctl enable containerd.service
# To disable this behavior, use disable instead.
# sudo systemctl disable docker.service
# sudo systemctl disable containerd.service

print_banner " Verifying Docker CLI..."
docker --version || echo "Docker CLI not available"

print_banner " Running test container... "

if docker run --rm hello-world; then
    print_banner "Docker was installed and is working correctly"
else
    print_banner "Error: Docker run failed. Try logging out and logging in again, or restarting your computer"
fi

# Configuration advice
cat <<'EOF'
*******************************************************************************************************
* By default configuration files for Docker are stored in the path "${HOME}/.docker".                 *
* It is possible to change the location of Docker configuration files from "${HOME}/.docker"          *
* to "${HOME}/.config/docker". You can achieve this by using the DOCKER_CONFIG environment variable.  *
* Here's how you can do it:                                                                           *
*                                                                                                     *
* 1. Create the path "${HOME}/.config/docker" if it doesn't exist:                                    *
*    mkdir -p "${HOME}/.config/docker"                                                                *
*                                                                                                     *
* 2. Set the DOCKER_CONFIG environment variable to point to the new location. You can do this by      *
*    adding the line                                                                                  *
*    export DOCKER_CONFIG="${HOME}/.config/docker"                                                    *
*    either to your shell rc file or profile file (e.g for bash ${HOME}/.bashrc or                    *
*    "${HOME}/.profile")                                                                              *
*                                                                                                     *
* 3. LOG OUT AND LOG BACK IN OR RESTART YOUR COMPUTER IF YOU PREFER TO APPLY THE CHANGES.             *
*******************************************************************************************************
EOF
