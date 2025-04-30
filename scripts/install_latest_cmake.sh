#!/bin/bash

# Reference: https://apt.kitware.com

[ "$(id --user)" -ne 0 ] && echo "root user must be active to run the script" && exit 1

echo "=================="
echo " Installing CMake "
echo "=================="

# Check if the repository from kitware has a more modern version of cmake for the distribution the
# image is being built.
if curl -s --head "https://apt.kitware.com/ubuntu/dists/${VERSION_CODENAME}/Release" | grep --quiet"200 OK"; then
    curl -fsSL https://apt.kitware.com/keys/kitware-archive-latest.asc | gpg --yes --dearmor --output /tmp/kitware-archive-keyring.gpg
    # -D: create all leading components of DEST except the last.
    install -D --owner root --group root --mode 644 /tmp/kitware-archive-keyring.gpg /etc/apt/keyrings/kitware-archive-keyring.gpg
    rm -f /tmp/kitware-archive-keyring.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${VERSION_CODENAME} main" | tee /etc/apt/sources.list.d/kitware.list
    apt-get update --quiet=1
    rm -f /etc/apt/keyrings/kitware-archive-keyring.gpg
    apt-get install --yes --quiet=1 --no-install-recommends kitware-archive-keyring
    apt-get install --yes --quiet=1 --no-install-recommends cmake cmake-data
elif
    # Install default cmake for the Ubuntu distribution ${VERSION_CODENAME}
    apt-get install --yes --quiet=1 --no-install-recommends cmake cmake-data
fi