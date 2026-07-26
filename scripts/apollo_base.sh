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
TOP_DIR="$(cd "$(dirname "${SH_SOURCE}")/.." && pwd)"
APOLLO_TOP_DIR="$(cd "$(dirname "${SH_SOURCE}")/../../../.." && pwd -P)"
ETC_DIR="${APOLLO_TOP_DIR}/etc"
PLUGIN_DIR="${ETC_DIR}/env_manager_plugin"
export APOLLO_ENVS_ROOT="${APOLLO_ENVS_ROOT:=$HOME/.aem/envs}"

buildtool="apollo-neo-buildtool-dev"
BUILD_TOOL="buildtool"

BOLD='\033[1m'
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[32m'
WHITE='\033[34m'
YELLOW='\033[33m'
NO_COLOR='\033[0m'

print_delim() {
    echo "=============================================="
}

get_now() {
    date +%s
}

time_elapsed_s() {
    local start="${1:-$(get_now)}"
    local end="$(get_now)"
    echo "$end - $start" | bc -l
}

success() {
    print_delim
    ok "$1"
    print_delim
}

fail() {
    print_delim
    error "$1"
    print_delim
    exit 1
}

file_ext() {
    local filename="$(basename $1)"
    local actual_ext="${filename##*.}"
    if [[ "${actual_ext}" == "${filename}" ]]; then
        actual_ext=""
    fi
    echo "${actual_ext}"
}

c_family_ext() {
    local actual_ext
    actual_ext="$(file_ext $1)"
    for ext in "h" "hh" "hxx" "hpp" "cxx" "cc" "cpp" "cu"; do
        if [[ "${ext}" == "${actual_ext}" ]]; then
            return 0
        fi
    done
    return 1
}

find_c_cpp_srcs() {
    find "$@" -type f -name "*.h" \
        -o -name "*.c" \
        -o -name "*.hpp" \
        -o -name "*.cpp" \
        -o -name "*.hh" \
        -o -name "*.cc" \
        -o -name "*.hxx" \
        -o -name "*.cxx" \
        -o -name "*.cu"
}

proto_ext() {
    if [[ "$(file_ext $1)" == "proto" ]]; then
        return 0
    else
        return 1
    fi
}

find_proto_srcs() {
    find "$@" -type f -name "*.proto"
}

py_ext() {
    if [[ "$(file_ext $1)" == "py" ]]; then
        return 0
    else
        return 1
    fi
}

find_py_srcs() {
    find "$@" -type f -name "*.py"
}

bash_ext() {
    local actual_ext
    actual_ext="$(file_ext $1)"
    for ext in "sh" "bash" "bashrc"; do
        if [[ "${ext}" == "${actual_ext}" ]]; then
            return 0
        fi
    done
    return 1
}

bazel_extended() {
    local actual_ext="$(file_ext $1)"
    if [[ -z "${actual_ext}" ]]; then
        if [[ "${arg}" == "BUILD" || "${arg}" == "WORKSPACE" ]]; then
            return 0
        else
            return 1
        fi
    else
        for ext in "BUILD" "bazel" "bzl"; do
            if [[ "${ext}" == "${actual_ext}" ]]; then
                return 0
            fi
        done
        return 1
    fi
}

prettier_ext() {
    local actual_ext
    actual_ext="$(file_ext $1)"
    for ext in "md" "json" "yml"; do
        if [[ "${ext}" == "${actual_ext}" ]]; then
            return 0
        fi
    done
    return 1
}

find_prettier_srcs() {
    find "$@" -type f -name "*.md" \
        -or -name "*.json" \
        -or -name "*.yml"
}

read_one_char_from_stdin() {
    local answer
    read -r -n1 answer
    # Bash 4.x+: ${answer,,} to lowercase, ${answer^^} to uppercase
    echo "${answer}" | tr '[:upper:]' '[:lower:]'
}

optarg_check_for_opt() {
    local opt="$1"
    local optarg="$2"
    if [[ -z "${optarg}" || "${optarg}" =~ ^-.* ]]; then
        error "Missing parameter for ${opt}. Exiting..."
        exit 3
    fi
}

info() {
    (echo >&2 -e "[${WHITE}${BOLD}INFO${NO_COLOR}] $*")
}

error() {
    (echo >&2 -e "[${RED}ERROR${NO_COLOR}] $*")
}

warning() {
    (echo >&2 -e "${YELLOW}[WARNING] $*${NO_COLOR}")
}

ok() {
    (echo >&2 -e "[${GREEN}${BOLD} OK ${NO_COLOR}] $*")
}

cmp_version() {
    local v1=$1
    local v2=$2
    if [[ $v1 == $v2 ]]; then
        echo 0
        return
    fi
    local vv="$(echo "${v1}\n${v2}" | sort -V | head -n1)"
    if [[ $vv == $v1 ]]; then
        echo -1
    else
        echo 1
    fi
}

docker_volume_exists() {
    local volume="${1}"
    local query="$(docker volume ls -q -f name=${volume} | grep "^${volume}$")"
    if [[ "${query}" == "${volume}" ]]; then
        return 0
    else
        return 1
    fi
}

docker_container_exists() {
    local container="${1}"
    local query="$(docker ps -a --format={{.Names}} -f name=${container} | grep "^${container}$"}})"
    if [[ "${query}" == "${container}" ]]; then
        return 0
    else
        return 1
    fi
}

docker_container_running() {
    local container="${1}"
    local query="$(docker ps --format={{.Names}} -f status=running -f name=${container} | grep "^${container}$")"
    if [[ "${query}" == "${container}" ]]; then
        return 0
    else
        return 1
    fi
}

docker_container_stopped() {
    local container="${1}"
    local query="$(docker ps --format={{.Names}} -f status=exited -f name=${container} | grep "^${container}$")"
    if [[ "${query}" == "${container}" ]]; then
        return 0
    else
        return 1
    fi
}

REPO_ADRESS="deb https://apollo-pkg-beta.cdn.bcebos.com/neo/beta bionic main"

check_in_dev_docker() {
    if [ ! -f /.dockerenv ]; then
        error "Outside from Apollo container env"
        return -1
    fi
    return 0
}

check_core_installed() {
    if [ ! -f /.installed ]; then
        error "Core module of apollo is not installed!"
        error "Please run \"aem install_core\" first!"
        return -1
    fi
    return 0
}

check_buildtool() {
    local result
    result=$(sudo apt list ${buildtool} 2>/dev/null | grep ${buildtool})
    if [[ $result == "" ]]; then
        add_repo
        sudo apt install -y --allow-unauthenticated ${buildtool}
        if [ $? -ne 0 ]; then
            echo "Failed to install ${buildtool}"
            exit -1
        fi
    else
        if [[ ! $result =~ "installed" ]]; then
            sudo apt install -y --allow-unauthenticated ${buildtool}
            if [ $? -ne 0 ]; then
                echo "Failed to install ${buildtool}"
                exit -1
            fi
        fi
    fi
}

add_repo() {
    local ubuntu_source="/etc/apt/sources.list"
    if [[ ! -z "$(cat $ubuntu_source | grep \"$REPO_ADRESS\")" ]]; then
        sudo bash -c "echo ${REPO_ADRESS} >> ${ubuntu_source}"
    fi
    sudo apt update --allow-insecure-repositories
}

postrun_start_user() {
    local container="$1"
    if [ "${USER}" != "root" ]; then
        docker exec -u root "${container}" \
            bash -c "${TOP_DIR}/scripts/docker_start_user.sh"
    fi
}

postrun_cross_platfrom_download() {
    local container="$1"
    local flag="$2"
    if [[ "$flag" -eq 1 ]]; then
        download_tegra_lib "${container}"
    fi
}

download_tegra_lib() {
    local container="$1"
    local tegra_lib_url="https://apollo-pkg-beta.cdn.bcebos.com/archive/tegra.tar.gz"
    info "download external library for cross-compilation..."
    docker exec -u root "${container}" \
        bash -c "cd ~ && wget -nv ${tegra_lib_url} && tar -xzvf ~/tegra.tar.gz -C /usr/lib/aarch64-linux-gnu/ > /dev/null"
}

stop_all_apollo_containers() {
    local force="$1"
    local running_containers
    if [[ "${force}" == "-f" || "${force}" == "--force" ]]; then
        warning "Parameter - f/-- force deleted"
    fi
    running_containers="$(docker ps -a --format '{{.Names}}')"
    for container in ${running_containers[*]}; do
        if [[ "${container}" =~ apollo_neo_.*_${USER} ]]; then
            #printf %-*s 70 "Now stop container: ${container} ..."
            #printf "\033[32m[DONE]\033[0m\n"
            #printf "\033[31m[FAILED]\033[0m\n"
            info "Now stop container ${container} ..."
            if docker stop "${container}" >/dev/null; then
                info "Done."
            else
                warning "Failed."
            fi
        fi
    done
}

# Check whether user has agreed license agreement
check_agreement() {
    local agreement_record="${HOME}/.apollo_agreement.txt"
    if [[ -e "${agreement_record}" ]]; then
        return 0
    fi
    local agreement_file
    agreement_file="${TOP_DIR}/scripts/AGREEMENT.txt"
    if [[ ! -f "${agreement_file}" ]]; then
        error "AGREEMENT ${agreement_file} does not exist."
        exit 1
    fi

    cat "${agreement_file}"
    local tip="Type 'y' or 'Y' to agree to the license agreement above, \
or type any other key to exit:"

    echo -n "${tip}"
    local answer="$(read_one_char_from_stdin)"
    echo

    if [[ "${answer}" != "y" ]]; then
        exit 1
    fi

    cp -f "${agreement_file}" "${agreement_record}"
    echo "${tip}" >>"${agreement_record}"
    echo "${user_agreed}" >>"${agreement_record}"
}

#export -f check_agreement
#export -f check_buildtool
#export -f add_repo
#export -f check_core_installed
#export -f check_in_dev_docker
