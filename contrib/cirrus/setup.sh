#!/usr/bin/env bash

set -e

FEDORA_PACKAGES="
    bats
    podman
    ShellCheck
    skopeo
    wget
"

source $(dirname $0)/lib.sh

show_env_vars

install_ooe

# When the fedora repos go down, it tends to last quite a while :(
timeout_attempt_delay_command 120s 3 120s dnf install -y \
    '@C Development Tools and Libraries' '@Development Tools' \
    $FEDORA_PACKAGES
