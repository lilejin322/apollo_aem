#!/usr/bin/env bash

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
TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${TOP_DIR}/scripts/apollo_base.sh"

conf_manager_script="${TOP_DIR}/scripts/conf_manager.py"
profiles_dir="${APOLLO_ENV_WORKROOT}/profiles"
conf_dir="/apollo"

check_profiles_dir() {
    if [ ! -d ${profiles_dir} ]; then
        error "profiles dir [${profiles_dir}] not exists!"
        return -1
    fi
    return 0
}

list() {
    check_profiles_dir || exit -1
    ls -l ${profiles_dir} | grep '^d' | awk '{print $NF}'
}

use() {
    if [ -z $1 ]; then
        error "profile name missing!"
        exit -1
    fi
    check_profiles_dir || exit -1

    target_profile="${profiles_dir}/${1}"
    if [ ! -d ${target_profile} ]; then
        error "${target_profile} dir not exists!"
        exit -1
    fi
    current_link="${profiles_dir}/current"
    ln -snf ${1} ${current_link}
    if [ $? -ne 0 ]; then
        error "create link from ${target_profile} to ${current_link} failed."
        exit -1
    fi
    sudo python3 ${conf_manager_script} update -s ${current_link} -t ${conf_dir} -f
    if [ $? -ne 0 ]; then
        error "update conf ${target_profile} failed."
        exit -1
    fi
    sudo python3 ${conf_manager_script} recover -t ${conf_dir}  -r ${APOLLO_DISTRIBUTION_HOME}/share
    if [ $? -ne 0 ]; then
        warning "recover invalid conf failed."
        exit -1
    fi
    ok "use profile ${1} successfully."
}

help() {
    echo "usage: ${0##*/} [-h] {list,use} ..."
}

parse_arguments() {
    case $1 in
        list)
            list
            ;;
        use)
            use $2
            ;;
        --help | -h)
            help
            ;;
        *)
            help
            ;;
    esac
}

main(){
    check_in_dev_docker
    if [ ! $? -eq 0 ]
    then
        exit -1
    fi
    parse_arguments $@
}

main $@
