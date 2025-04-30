#!/bin/bash

# Reference:https://code.visualstudio.com/docs/setup/linux#_install-vs-code-on-linux

echo "=================================="
echo " Installing VSCode and extensions "
echo "=================================="

sudo apt-get install --yes --quiet --no-install-recommends wget gpg apt-transport-https
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
rm -f packages.microsoft.gpg
sudo apt-get update
sudo apt-get install --yes --quiet --no-install-recommends code

EXTENSIONS=(
cheshirekow.cmake-format
cschlosser.doxdocgen
davidanson.vscode-markdownlint
dotjoshjohnson.xml
eamodio.gitlens
foxundermoon.shell-format
github.copilot
github.copilot-chat
github.remotehub
ibm.output-colorizer
mechatroner.rainbow-csv
mhutchie.git-graph
ms-azuretools.vscode-docker
ms-iot.vscode-ros
ms-python.black-formatter
ms-python.debugpy
ms-python.flake8
ms-python.isort
ms-python.python
ms-python.vscode-pylance
ms-vscode.cpptools-extension-pack
ms-vscode.hexeditor
ms-vscode-remote.remote-containers
ms-vscode.remote-explorer
ms-vscode.remote-repositories
ms-vscode-remote.remote-ssh
ms-vscode-remote.remote-ssh-edit
ms-vscode.remote-server
ms-vscode-remote.vscode-remote-extensionpack
redhat.vscode-yaml
ryzngard.vscode-header-source
tamasfe.even-better-toml
yzhang.markdown-all-in-one
)

for extension in "${EXTENSIONS[@]}"; do
    code --install-extension "${extension}" --force
done