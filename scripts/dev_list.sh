###############################################################################
# Copyright 2023 The Apollo Authors. All Rights Reserved.
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
APOLLO_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${APOLLO_ROOT_DIR}/scripts/apollo_base.sh"

APOLLO_ENV_WORKSPACE="${PWD}"
APOLLO_ENV_CONTAINER_PREFIX="apollo_neo_dev_"
APOLLO_ENV_NAME="${APOLLO_ENV_NAME:=${USER}}"
APOLLO_ENV_WORKROOT=${APOLLO_ENV_WORKROOT:='/apollo_workspace'}

# override environment variables
[[ -e "$PWD/.env" ]] && set -a && source "$PWD/.env" && set +a

# derived variables
DEV_CONTAINER="${APOLLO_ENV_CONTAINER_PREFIX}${APOLLO_ENV_NAME}"

show_usage() {
    cat <<EOF
Usage: aem [options] ...
OPTIONS:
    -h, --help                    Display this help and exit.
    --user                        Filter containers by user.
    list                          Show Apollo containers.
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

            --user)
                # TODO: filter containers by user
                export CUSTOM_USER="$1"
                shift
                ;;
        esac
    done
}

list_env_containers() {
    local env_containers=$(docker ps -a --format '{{.Names}}' | grep "${APOLLO_ENV_CONTAINER_PREFIX}")
    if [[ -z "${env_containers}" ]]; then
        warning "No environment containers found."
        return 1
    fi

    info "Environment containers:"
    for x in ${env_containers}; do
        local envhome="${APOLLO_ENVS_ROOT}/${x}"
        if [[ -e "${envhome}" ]]; then
            echo "${x} ${envhome}"
        elif docker_volume_exists "${x}_opt"; then
            opt_vol="$(docker volume inspect "${x}_opt" --format '{{.Options.device}}')"
            echo "${x} ${opt_vol%/envroot/opt}"
        else
            echo "${x}"
        fi
    done
}

main() {
    parse_arguments "$@"
    list_env_containers
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, do nothing
    :
else
    main "$@"
fi
