#!/bin/bash

sudo apt-get update

# The command ripgrep is a better version of grep command.
# Install ripgrep from the package manager if available, otherwise download it from github and install it.
ripgrep_in_package_manager="$(apt-cache search --names-only '^ripgrep$')"

if [ -n "${ripgrep_in_package_manager}" ]; then
  apt-get install --yes --quiet --no-install-recommends ripgrep
else
  ripgrep_version=$(curl -s "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" | grep -Po '"tag_name": "\K[0-9.]+')

  if [ -n "${ripgrep_version}" ]; then
    echo "Install ripgrep version: ${ripgrep_version}"
    curl -s "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" | grep -Po "browser_download_url.*deb" | cut -d: -f 2,3 | tr -d \" | uniq | wget -i - -O /tmp/ripgrep.deb
    chmod +x /tmp/ripgrep.deb
    dpkg -i /tmp/ripgrep.deb
    rm -f /tmp/ripgrep.deb
  fi
fi