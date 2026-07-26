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
APOLLO_ENV_WORKLOCAL=0

# override environment variables
[[ -e "$PWD/.env" ]] && set -a && source "$PWD/.env" && set +a

# derived variables
DEV_CONTAINER="${APOLLO_ENV_CONTAINER_PREFIX}${APOLLO_ENV_NAME}"

parse_arguments() {
    local container_name=''

    while [ $# -gt 0 ]; do
        local opt="$1"
        shift
        case "${opt}" in
            -n | --name)
                container_name="$1"
                DEV_CONTAINER="${APOLLO_ENV_CONTAINER_PREFIX}${container_name}"
                shift
                ;;

            -w | --workspace)
                APOLLO_ENV_WORKSPACE="$1"
                shift
                ;;

            --worklocal)
                APOLLO_ENV_WORKLOCAL=1
                ;;
        esac
    done
}

remove_env_container() {
    info "Removing container ${DEV_CONTAINER}"
    docker rm -f "${DEV_CONTAINER}" 1>/dev/null 2>&1
}

remove_envhome() {
    local envhome="${APOLLO_ENVS_ROOT}/${DEV_CONTAINER}"
    if [[ "${APOLLO_ENV_WORKLOCAL}" == "1" ]]; then
        envhome="${APOLLO_ENV_WORKSPACE}/.aem"
    fi
    local envroot="${envhome}/envroot"
    info "Removing container volumes for ${DEV_CONTAINER}"
    for x in apollo opt; do
        local vol="${DEV_CONTAINER}_${x}"
        vol_dev="$(docker volume inspect "${vol}" --format '{{.Options.device}}')"
        info "Removing volume ${vol} ${vol_dev}"
        docker volume rm -f "${vol}" 1>/dev/null 2>&1
        sudo rm -rf ${envroot}/${x}
    done
    info "Removing ${envhome}"
    sudo rm -rf "${envhome}"

    if [[ "${APOLLO_ENV_WORKLOCAL}" == "0" ]]; then
        if [[ -L "${APOLLO_ENV_WORKSPACE}/.aem/envroot" ]]; then
            if [[ ! -e "${APOLLO_ENV_WORKSPACE}/.aem/envroot" ]]; then
                # deadlink, remove it
                rm -f "${APOLLO_ENV_WORKSPACE}/.aem/envroot"
            elif [[ "$(readlink "${APOLLO_ENV_WORKSPACE}/.aem/envroot")" == "${envroot}" ]]; then
                rm -f "${APOLLO_ENV_WORKSPACE}/.aem/envroot"
            fi
        fi
    fi
}

main() {
    parse_arguments "$@"
    remove_env_container
    remove_envhome
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, do nothing
    :
else
    main "$@"
fi
