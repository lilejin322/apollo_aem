###############################################################################
# Copyright 2017 The Apollo Authors. All Rights Reserved.
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
    -n, --name                    specify container name to enter.
    --user                        specify container user to enter
    enter                         Enter Apollo containers.
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

            -n | --name)
                container_name="$1"
                DEV_CONTAINER="${APOLLO_ENV_CONTAINER_PREFIX}${container_name}"
                shift
                ;;

            --user)
                export CUSTOM_USER="$1"
                shift
                ;;
        esac
    done
}

start_stopped_container() {
    if docker_container_stopped "${DEV_CONTAINER}"; then
        docker start "${DEV_CONTAINER}" 1>/dev/null
    fi
}

check_container_exists() {
  if docker_container_exists "${DEV_CONTAINER}"; then
    return 0
  fi
  error "container ${DEV_CONTAINER} not exists. \n \
         1.Please confirm that the container has started first? If not, please execute aem start first. \n \
         2.If you specified the container name through the -n parameter, please confirm if the parameter is correct. \n \
         3.If you did not specify the container name through the -n parameter, please enter the project directory and execute aem enter again"
  return 1
}

main() {
    parse_arguments "$@"

    check_container_exists
    if [ ! $? -eq 0 ]
    then
        exit 1
    fi

    start_stopped_container

    # passthrough all APOLLO_ENV_* variables
    local envs=()
    for x in ${!APOLLO_ENV_@}; do
        envs[${#envs[@]}]="-e ${x}=${!x}"
    done

    # Allow X server connection from container.
    xhost +local:root 1>/dev/null 2>&1

    local user="${CUSTOM_USER-$USER}"

    docker exec \
        -u "${user}" \
        -e HISTFILE=/apollo_workspace/.cache/.bash_history \
        -e DOCKER_USER="${user}" \
        ${envs[@]} \
        -w ${APOLLO_ENV_WORKROOT} \
        -it "${DEV_CONTAINER}" \
        /bin/bash

    xhost -local:root 1>/dev/null 2>&1
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, do nothing
    :
else
    main "$@"
fi
