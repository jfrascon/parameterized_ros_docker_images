#!/bin/bash

echo "================"
echo " Installing gcc "
echo "================"

sudo add-apt-repository ppa:ubuntu-toolchain-r/test --yes
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-all" dist-upgrade --yes
# Get the latest version of gcc automatically from the package repo.
gcc_version="$(apt-cache search gcc | awk '/^gcc-[0-9]{2} - / {print $1}' | cut -d- -f2 | sort -r | sed 1q)"
sudo apt-get install --yes --quiet --no-install-recommends gcc-${gcc_version} g++-${gcc_version} gdb gdbserver

sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${gcc_version} 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${gcc_version} 100
sudo update-alternatives --install /usr/bin/cc  cc  /usr/bin/gcc-${gcc_version} 100
sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-${gcc_version} 100
