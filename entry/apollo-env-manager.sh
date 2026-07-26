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
SH_SOURCE=$(realpath ${BASH_SOURCE[0]})
TOP_DIR="$(cd "$(dirname "${SH_SOURCE}")/.." && pwd -P)"
source "${TOP_DIR}/scripts/apollo_base.sh"

declare -A COMMAND_DESC_MAP=(
    ["create"]="create a new container with apollo development image."
    ["start"]="start the created container."
    ["start_gpu"]="start a created gpu container."
    ["enter"]="enter into the apollo development container."
    ["remove"]="remove the apollo development container."
    ["list"]="list all apollo development container."
    ["bootstrap"]="run dreamview and monitor module."
    ["build"]="build package in workspace."
    ["install"]="install source code of specified package to workspace."
    ["init"]="init single workspace."
    ["update"]="update core modules of apollo."
    ["stopall"]="stop all apollo development container."
    ["setup_host"]="setup host"
    ["profile"]="profiles management"
)

declare -A COMMAND_SCRIPT_MAP=(
    ["create"]="${TOP_DIR}/scripts/dev_start.sh -f"
    ["start"]="${TOP_DIR}/scripts/dev_start.sh"
    ["start_gpu"]="${TOP_DIR}/scripts/dev_start.sh --gpu"
    ["enter"]="${TOP_DIR}/scripts/dev_into.sh"
    ["remove"]="${TOP_DIR}/scripts/dev_remove.sh"
    ["list"]="${TOP_DIR}/scripts/dev_list.sh"
    ["stopall"]="${TOP_DIR}/scripts/dev_stopall.sh"
    ["bootstrap"]="${TOP_DIR}/scripts/bootstrap.sh"
    ["build"]="${TOP_DIR}/scripts/apollo_build.sh"
    ["install"]="${TOP_DIR}/scripts/apollo_install.sh" 
    ["init"]="${TOP_DIR}/scripts/apollo_init.sh"
    ["update"]="${TOP_DIR}/scripts/update.sh"
    ["setup_host"]="${TOP_DIR}/scripts/setup_host.sh"
    ["profile"]="${TOP_DIR}/scripts/profile_manager.sh"
)

function _search_available_plugin() {
    if [[ ! -d ${PLUGIN_DIR} ]]; then
        return
    fi
    for file in $(ls ${PLUGIN_DIR}/*.sh)
    do
        command_name="$(echo ${file} | sed 's/\.[^.]*$//')"
        desc_file="${command_name}.desc"
        command_name="${command_name##*/}"
        if [[ ! -f "${file}" ]]; then continue; fi
        if [[ ! -f "${desc_file}" ]]; then continue; fi
        _overwrite_or_add_command "${command_name}" "${desc_file}" "${file}"
    done
    return
}

function _overwrite_or_add_command() {
    if [[ ! -f "$2" ]]; then
        echo >&2 -e "[${RED}ERROR${NO_COLOR}] fail to load plugin $1: $2 not exists!"
        return
    fi
    if [[ ! -f "$3" ]]; then
        echo >&2 -e "[${RED}ERROR${NO_COLOR}] fail to load plugin $1: $3 not exists!"
        return 
    fi 
    plugin_desc_content="$(cat $2)"
    COMMAND_DESC_MAP["$1"]="$plugin_desc_content"
    COMMAND_SCRIPT_MAP["$1"]="$3"
}

function _usage() {
    echo -e "\n${RED}Usage${NO_COLOR}:
    ${BOLD}aem${NO_COLOR} [OPTION]"
    echo -e "\n${RED}Options${NO_COLOR}:"
    for key in ${!COMMAND_DESC_MAP[@]} 
    do
        echo -e "    ${BOLD}${key} ${NO_COLOR}: ${COMMAND_DESC_MAP[${key}]}"
    done
}


function main() {
    _search_available_plugin
    if [ "$#" -eq 0 ]; then
        _usage
        exit 0
    fi
    
    local cmd=$1

    case $1 in 
        -h | --help | usage | Usage)
            _usage
            ;; 
        *)
            shift
            if [[ ! -n ${COMMAND_DESC_MAP[$cmd]} ]]; then
                _usage
            else
                bash ${COMMAND_SCRIPT_MAP[$cmd]} $@
            fi
            ;;
    esac
}

main $@
