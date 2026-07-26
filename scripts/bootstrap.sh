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
source ~/.bashrc

DREAMVIEW_URL="http://localhost"
DV_PLUS_PORT=8888
DV_PORT=8899

start() {
    DV_ORIGIN=0
    if [[ -z "${APOLLO_DISTRIBUTION_VERSION}" ]]; then
        warning "APOLLO_DISTRIBUTION_VERSION is not set. fallback to 8.0"
        ${BUILD_TOOL} bootstrap start dreamview-dev
        ${BUILD_TOOL} bootstrap start monitor-dev
    else
        case $1 in
            --plus)
                ${BUILD_TOOL} bootstrap start dreamview_plus
                ${BUILD_TOOL} bootstrap start monitor
                ;;
            *)
                DV_ORIGIN=1
                ${BUILD_TOOL} bootstrap start dreamview
                ${BUILD_TOOL} bootstrap start monitor
                ;;
        esac
    fi
    sleep 5 # wait for some time before starting to check
    if [ $DV_ORIGIN -eq 1 ]; then
        DREAMVIEW_URL_WITH_PORT="${DREAMVIEW_URL}:${DV_PORT}"
    else
        DREAMVIEW_URL_WITH_PORT="${DREAMVIEW_URL}:${DV_PLUS_PORT}" 
    fi
    http_status="$(curl -o /dev/null -x '' -I -L -s -w '%{http_code}' ${DREAMVIEW_URL_WITH_PORT})"
    if [ $http_status -eq 200 ]; then
        info "Dreamview is running at" $DREAMVIEW_URL_WITH_PORT
    else
        error "Failed to start Dreamview. Please check /opt/apollo/neo/data/log/dreamview.log or /opt/apollo/neo/data/log/monitor.log for more information"
    fi
}

stop() {
    if [[ -z "${APOLLO_DISTRIBUTION_VERSION}" ]]; then
        ${BUILD_TOOL} bootstrap stop dreamview-dev >/dev/null 2>&1
        ${BUILD_TOOL} bootstrap stop monitor-dev >/dev/null 2>&1
    else
        ${BUILD_TOOL} bootstrap stop dreamview >/dev/null 2>&1
        ${BUILD_TOOL} bootstrap stop dreamview_plus >/dev/null 2>&1
        ${BUILD_TOOL} bootstrap stop monitor >/dev/null 2>&1
    fi
    info "complete."
}

help() {
    cat <<EOF
Usage: aem bootstrap [options] [argument] ...
OPTIONS:
    start --plus                    Start dreamview 2.0.
    start                           Start dreamview.
    stop                            Stop dreamview or dreamview 2.0.
EOF
}

parse_arguments() {
    case $1 in
        start)
            shift
            start $@
            ;;
        stop)
            stop
            ;;
        restart)
            stop
            shift
            start $@
            ;;
        --help | -h)
            help
            ;;
        *)
            help
            ;;
    esac
}

main() {
    check_in_dev_docker
    if [ ! $? -eq 0 ]; then
        exit -1
    fi

    check_core_installed
    if [ ! $? -eq 0 ]; then
        exit -1
    fi
    parse_arguments $@
}

main $@
