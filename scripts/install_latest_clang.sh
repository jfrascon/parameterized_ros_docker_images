#!/bin/bash

# Reference: https://apt.llvm.org

echo "=================="
echo " Installing clang "
echo "=================="

wget -O /tmp/llvm.sh https://apt.llvm.org/llvm.sh
# Get the latest version of clang from the llvm script.
clang_version="$(awk -F= '/CURRENT_LLVM_STABLE=/ {print $2}' /tmp/llvm.sh)"
curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | gpg --dearmor > llvm.gpg
sudo install -D -o root -g root -m 644 llvm.gpg /etc/apt/keyrings/llvm.gpg
rm -f llvm.gpg
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/${VERSION_CODENAME}/ llvm-toolchain-${VERSION_CODENAME}-${clang_version} main" | sudo tee /etc/apt/sources.list.d/llvm.list
sudo apt-get update
sudo apt-get -o Dpkg::Options::="--force-all" dist-upgrade --yes
sudo apt-get install --yes --quiet --no-install-recommends clang-${clang_version} lldb-${clang_version} lld-${clang_version} clangd-${clang_version} clang-tidy-${clang_version} clang-format-${clang_version} clang-tools-${clang_version} llvm-${clang_version}-dev llvm-${clang_version}-tools libomp-${clang_version}-dev libc++-${clang_version}-dev libc++abi-${clang_version}-dev libclang-common-${clang_version}-dev libclang-${clang_version}-dev libclang-cpp${clang_version}-dev libunwind-${clang_version}-dev
sudo update-alternatives --install /usr/bin/llvm-config           llvm-config           /usr/bin/llvm-config-${clang_version}           100
sudo update-alternatives --install /usr/bin/llvm-ar               llvm-ar               /usr/bin/llvm-ar-${clang_version}               100
sudo update-alternatives --install /usr/bin/llvm-as               llvm-as               /usr/bin/llvm-as-${clang_version}               100
sudo update-alternatives --install /usr/bin/llvm-bcanalyzer       llvm-bcanalyzer       /usr/bin/llvm-bcanalyzer-${clang_version}       100
sudo update-alternatives --install /usr/bin/llvm-cov              llvm-cov              /usr/bin/llvm-cov-${clang_version}              100
sudo update-alternatives --install /usr/bin/llvm-diff             llvm-diff             /usr/bin/llvm-diff-${clang_version}             100
sudo update-alternatives --install /usr/bin/llvm-dis              llvm-dis              /usr/bin/llvm-dis-${clang_version}              100
sudo update-alternatives --install /usr/bin/llvm-dwarfdump        llvm-dwarfdump        /usr/bin/llvm-dwarfdump-${clang_version}        100
sudo update-alternatives --install /usr/bin/llvm-extract          llvm-extract          /usr/bin/llvm-extract-${clang_version}          100
sudo update-alternatives --install /usr/bin/llvm-link             llvm-link             /usr/bin/llvm-link-${clang_version}             100
sudo update-alternatives --install /usr/bin/llvm-mc               llvm-mc               /usr/bin/llvm-mc-${clang_version}               100
sudo update-alternatives --install /usr/bin/llvm-nm               llvm-nm               /usr/bin/llvm-nm-${clang_version}               100
sudo update-alternatives --install /usr/bin/llvm-objcopy          llvm-objcopy          /usr/bin/llvm-objcopy-${clang_version}          100
sudo update-alternatives --install /usr/bin/llvm-objdump          llvm-objdump          /usr/bin/llvm-objdump-${clang_version}          100
sudo update-alternatives --install /usr/bin/llvm-ranlib           llvm-ranlib           /usr/bin/llvm-ranlib-${clang_version}           100
sudo update-alternatives --install /usr/bin/llvm-readobj          llvm-readobj          /usr/bin/llvm-readobj-${clang_version}          100
sudo update-alternatives --install /usr/bin/llvm-rtdyld           llvm-rtdyld           /usr/bin/llvm-rtdyld-${clang_version}           100
sudo update-alternatives --install /usr/bin/llvm-size             llvm-size             /usr/bin/llvm-size-${clang_version}             100
sudo update-alternatives --install /usr/bin/llvm-stress           llvm-stress           /usr/bin/llvm-stress-${clang_version}           100
sudo update-alternatives --install /usr/bin/llvm-strip            llvm-strip            /usr/bin/llvm-strip-${clang_version}            100
sudo update-alternatives --install /usr/bin/llvm-symbolizer       llvm-symbolizer       /usr/bin/llvm-symbolizer-${clang_version}       100
sudo update-alternatives --install /usr/bin/llvm-tblgen           llvm-tblgen           /usr/bin/llvm-tblgen-${clang_version}           100
sudo update-alternatives --install /usr/bin/clang                 clang                 /usr/bin/clang-${clang_version}                 100
sudo update-alternatives --install /usr/bin/clang++               clang++               /usr/bin/clang++-${clang_version}               100
sudo update-alternatives --install /usr/bin/asan_symbolize        asan_symbolize        /usr/bin/asan_symbolize-${clang_version}        100
sudo update-alternatives --install /usr/bin/c-index-test          c-index-test          /usr/bin/c-index-test-${clang_version}          100
sudo update-alternatives --install /usr/bin/clang-check           clang-check           /usr/bin/clang-check-${clang_version}           100
sudo update-alternatives --install /usr/bin/clang-cl              clang-cl              /usr/bin/clang-cl-${clang_version}              100
sudo update-alternatives --install /usr/bin/clang-cpp             clang-cpp             /usr/bin/clang-cpp-${clang_version}             100
sudo update-alternatives --install /usr/bin/clang-format          clang-format          /usr/bin/clang-format-${clang_version}          100
sudo update-alternatives --install /usr/bin/clang-format-diff     clang-format-diff     /usr/bin/clang-format-diff-${clang_version}     100
sudo update-alternatives --install /usr/bin/clang-include-fixer   clang-include-fixer   /usr/bin/clang-include-fixer-${clang_version}   100
sudo update-alternatives --install /usr/bin/clang-offload-bundler clang-offload-bundler /usr/bin/clang-offload-bundler-${clang_version} 100
sudo update-alternatives --install /usr/bin/clang-query           clang-query           /usr/bin/clang-query-${clang_version}           100
sudo update-alternatives --install /usr/bin/clang-rename          clang-rename          /usr/bin/clang-rename-${clang_version}          100
sudo update-alternatives --install /usr/bin/clang-reorder-fields  clang-reorder-fields  /usr/bin/clang-reorder-fields-${clang_version}  100
sudo update-alternatives --install /usr/bin/clang-tidy            clang-tidy            /usr/bin/clang-tidy-${clang_version}            100
sudo update-alternatives --install /usr/bin/ld.lld                ld.lld                /usr/bin/ld.lld-${clang_version}                100
sudo update-alternatives --install /usr/bin/lld                   lld                   /usr/bin/lld-${clang_version}                   100
sudo update-alternatives --install /usr/bin/lld-link              lld-link	             /usr/bin/lld-link-${clang_version}              100
sudo update-alternatives --install /usr/bin/lldb                  lldb                  /usr/bin/lldb-${clang_version}                  100
sudo update-alternatives --install /usr/bin/lldb-server           lldb-server           /usr/bin/lldb-server-${clang_version}           100
rm /tmp/llvm.sh
