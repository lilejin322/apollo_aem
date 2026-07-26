#!/usr/bin/env bash

###############################################################################
# Copyright 2017-2021 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${TOP_DIR}/scripts/apollo_base.sh"

show_usage() {
    cat <<EOF
Usage: aem [options] ...
OPTIONS:
    -h, --help                    Display this help and exit.
    update                        Update aem.
EOF
}

parse_arguments() {
    local container_name=''

    while [ $# -gt 0 ]; do
        local opt="$1"
        shift
        case "${opt}" in
            -h | --help)
                show_usage
                exit 1
                ;;
        esac
    done
}

function main() {
    parse_arguments "$@"
    check_in_dev_docker
    if [ ! $? -eq 0 ]; then exit -1; fi
    if [ -f /.installed ]
    then
        sudo apt update --allow-insecure-repositories
        sudo apt install --only-upgrade -y --allow-unauthenticated apollo-neo-cyber-dev apollo-neo-common-dev apollo-neo-common-msgs-dev apollo-neo-buildtool-dev
    else
        error "Core module have not been installed"
    fi
    info "Core module have been updated"
}

main $@
