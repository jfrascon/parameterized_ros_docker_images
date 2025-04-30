#!/bin/bash

# Latest git and friends
add-apt-repository --yes ppa:git-core/ppa
apt-get update --quiet=1
apt-get dist-upgrade --yes
apt-get install --yes --quiet=1 --no-install-recommends git git-core git-all
