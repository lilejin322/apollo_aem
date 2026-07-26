#!/usr/bin/env bash

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

# Global variables
APOLLO_ENV_CONTAINER_PREFIX="apollo_neo_dev_"
APOLLO_ENV_NAME="${APOLLO_ENV_NAME:=${USER}}"
APOLLO_ENV_WORKSPACE="${PWD}"
APOLLO_ENV_WORKROOT=${APOLLO_ENV_WORKROOT:='/apollo_workspace'}
APOLLO_ENV_WORKLOCAL=0
APOLLO_ENV_CONTAINER_REPO=
APOLLO_ENV_CONTAINER_TAG=
APOLLO_ENV_CONTAINER_REPO_X86='registry.baidubce.com/apollo/apollo-env-gpu'
APOLLO_ENV_CONTAINER_REPO_ARM='registry.baidubce.com/apollo/apollo-env-arm'
DEV_INSIDE="in-dev-docker"
DEV_CONTAINER_MOUNT_DIR=$APOLLO_ROOT_DIR
SUPPORTED_ARCHS=(x86_64 aarch64)
DOCKER_RUN_CMD="docker run"
# deprecated, will be removed in the future
DOCKER_REPO_X86='registry.baidubce.com/apollo/apollo-env-gpu'
# deprecated, will be removed in the future
DOCKER_REPO_ARM='registry.baidubce.com/apollo/apollo-env-arm'
# deprecated, will be removed in the future
DOCKER_REPO=
# deprecated, will be removed in the future
VERSION=

# Flags, controlled by command line arguments
USE_GPU_IMAGE=0
USE_GPU_HOST=
USER_VERSION_OPT=
FORCE_RECREATE_CONTAINER=0
USE_LOCAL_IMAGE=0
USER_AGREED="no"
SHM_SIZE="2G"
CROSS_PLATFORM_FLAG=0
CUSTOM_MOUNT_PATH=()

# override environment variables
[[ -e "$PWD/.env" ]] && set -a && source "$PWD/.env" && set +a

# derived variables, cannot be overrided
DEV_CONTAINER="${APOLLO_ENV_CONTAINER_PREFIX}${APOLLO_ENV_NAME}"
TARGET_ARCH="$(uname -m)"
HOST_OS="$(uname -s)"

show_usage() {
    cat <<EOF
Usage: aem [options] ...
OPTIONS:
    -h, --help                    Display this help and exit.
    -f, --force                   force to restart the container.
    -n, --name                    specify container name to start a container.
    -m, --mount                   specify the mount point in container, such as /home/apollo/workspace:/apollo_workspace
    -g, --geo <us|cn|none>        Pull docker image from geolocation specific registry mirror.
    -t, --tag <TAG>               Specify docker image with tag <TAG> to start.
    -c, --cross-platform <arch>   Run a cross-platform image
    -y                            Agree to Apollo License Agreement non-interactively.
    --shm-size <bytes>            Size of /dev/shm . Passed directly to "docker run"
    --gpu                         Use gpu mode to start container.
    --gpu                         Use cpu mode to start container.
    stop                          Stop all running Apollo containers.
EOF
}

cross_platform_setup() {
    info "Setup qemu user static..."
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes -c yes >/dev/null
    if [[ ! $? -eq 0 ]]; then
        error "Qemu setup failed! Please report this issue to Apollo team."
        exit -1
    fi
}

parse_arguments() {
    local custom_version=""
    local shm_size=""
    local geo=""

    while [ $# -gt 0 ]; do
        local opt="$1"
        shift
        case "${opt}" in
            -t | --tag)
                if [ -n "${CUSTOM_CONTAINER_TAG}" ]; then
                    warning "Multiple option ${opt} specified, only the last one will take effect."
                fi
                CUSTOM_CONTAINER_TAG="$1"
                shift
                optarg_check_for_opt "${opt}" "${CUSTOM_CONTAINER_TAG}"
                ;;

            -c | --cross-platform)
                custom_arch="$1"
                shift
                if [[ "$TARGET_ARCH" == "aarch64" && "$custom_arch" == "x86_64" ]]; then
                    error "Run x86_64 image on aarch64 currently is not supported!"
                    exit -1
                fi
                if [[ ! "$TARGET_ARCH" == "$custom_arch"  ]]; then
                    CROSS_PLATFORM_FLAG=1
                fi
                TARGET_ARCH="$custom_arch"
                check_target_arch
                cross_platform_setup
                ;;

            -f | --force)
                FORCE_RECREATE_CONTAINER=1
                ;;

            -l | --local)
                USE_LOCAL_IMAGE=1
                ;;

            -w | --workspace)
                APOLLO_ENV_WORKSPACE="$1"
                shift
                ;;

            --worklocal)
                APOLLO_ENV_WORKLOCAL=1
                ;;

            -m | --mount)
                while [ ! $1 = -* ]; do
                    CUSTOM_MOUNT_PATH[${#CUSTOM_MOUNT_PATH[@]}]=$1
                    shift
                done
                ;;

            -y)
                USER_AGREED="yes"
                ;;

            --user)
                export CUSTOM_USER="$1"
                shift
                ;;

            --uid)
                export CUSTOM_UID="$1"
                shift
                ;;

            --group)
                export CUSTOM_GROUP="$1"
                shift
                ;;
            --gid)
                export CUSTOM_GID="$1"
                shift
                ;;

            --gpu)
                USE_GPU_HOST=1
                ;;

            --cpu)
                USE_GPU_HOST=0
                ;;

            -n | --name)
                container_name="$1"
                DEV_CONTAINER="${APOLLO_ENV_CONTAINER_PREFIX}${container_name}"
                shift
                ;;

            -h | --help)
                show_usage
                exit 1
                ;;

            --shm-size)
                shm_size="$1"
                shift
                optarg_check_for_opt "${opt}" "${shm_size}"
                ;;

            stop)
                info "Now, stop all Apollo containers created by ${USER} ..."
                stop_all_apollo_containers "-f"
                exit 0
                ;;

            *)
                warning "Unknown option: ${opt}"
                exit 2
                ;;
        esac
    done # End while loop

    [[ -n "${custom_version}" ]] && USER_VERSION_OPT="${custom_version}"
    [[ -n "${shm_size}" ]] && SHM_SIZE="${shm_size}"
}

setup_extra_volumes() {
    local ws_in_host="${APOLLO_ENV_WORKSPACE:-$PWD}"
    local flag_custom_ws=0
    local flag_custom_data=0
    local flag_custom_output=0
    local flag_custom_log=0
    local flag_custom_calibration=0
    local flag_custom_map=0

    local volumes=''
    for i in "${!CUSTOM_MOUNT_PATH[@]}"; do
        local mount_dst="${CUSTOM_MOUNT_PATH[i]}"
        if [[ "${CUSTOM_MOUNT_PATH[i]}" =~ "${APOLLO_TOP_DIR}" ]]; then
            error "mount path ${CUSTOM_MOUNT_PATH[i]} invalid!"
            continue
        fi
        if [[ "${CUSTOM_MOUNT_PATH[i]}" =~ ":" ]]; then
            volumes="${volumes} -v ${CUSTOM_MOUNT_PATH[i]}"
            mount_dst="${CUSTOM_MOUNT_PATH[i]#*:}"
            mount_src="${CUSTOM_MOUNT_PATH[i]%*:}"
        else
            volumes="${volumes} -v ${CUSTOM_MOUNT_PATH[i]}:${CUSTOM_MOUNT_PATH[i]}"
        fi
        if [[ "${mount_dst}" == "${APOLLO_ENV_WORKROOT}" ]]; then
            flag_custom_ws=1
            if [[ ! -d "${mount_src}/log" ]]; then
                mkdir -p "${mount_src}/log"
            fi
        fi
        if [[ "${mount_dst}" == '/apollo/data' ]]; then
            flag_custom_data=1
        fi
        if [[ "${mount_dst}" == '/apollo/output' ]]; then
            flag_custom_output=1
        fi
        if [[ "${mount_dst}" == "$APOLLO_TOP_DIR/data/log" ]]; then
            flag_custom_log=1
        fi
        if [[ "${mount_dst}" == "$APOLLO_TOP_DIR/modules/calibration/data" ]]; then
            flag_custom_calibration=1
        fi
        if [[ "${mount_dst}" == "$APOLLO_TOP_DIR/modules/map/data" ]]; then
            flag_custom_map=1
        fi
    done
    if [[ "${flag_custom_ws}" == "0" ]]; then
        volumes="${volumes} -v ${ws_in_host}:${APOLLO_ENV_WORKROOT}"
    fi
    if [[ "${flag_custom_data}" == "0" ]]; then
        bash -c "mkdir -p $ws_in_host/data/log"
        volumes="${volumes} -v $ws_in_host/data:/apollo/data"
    fi
    if [[ "${flag_custom_output}" == "0" ]]; then
        bash -c "mkdir -p $ws_in_host/output"
        volumes="${volumes} -v $ws_in_host/output:/apollo/output"
    fi
    if [[ "${flag_custom_log}" == "0" ]]; then
        volumes="${volumes} -v $ws_in_host/data/log:$APOLLO_TOP_DIR/data/log"
    fi
    if [[ "${flag_custom_calibration}" == "0" ]]; then
        bash -c "mkdir -p $ws_in_host/data/calibration_data"
        volumes="${volumes} -v $ws_in_host/data/calibration_data:/apollo/modules/calibration/data"
    fi
    if [[ "${flag_custom_map}" == "0" ]]; then
        bash -c "mkdir -p $ws_in_host/data/map_data"
        volumes="${volumes} -v $ws_in_host/data/map_data:/apollo/modules/map/data"
    fi
    tegrastats="/usr/bin/tegrastats"
    if [[ -x ${tegrastats} ]]; then
        volumes="${volumes} -v ${tegrastats}:${tegrastats}"
    fi

    volumes="${volumes} -v ${APOLLO_ROOT_DIR}:${DEV_CONTAINER_MOUNT_DIR}"
    echo "${volumes}"
}

run_in_container_as_root() {
    docker exec -u root ${DEV_CONTAINER} bash -c "$*"
}

postrun_link_aem_and_install_core_pkgs() {
    run_in_container_as_root "ln -snf ${DEV_CONTAINER_MOUNT_DIR}/entry/apollo-env-manager.sh /usr/local/bin/aem && ln -snf ${DEV_CONTAINER_MOUNT_DIR} ${DEV_CONTAINER_MOUNT_DIR}/../latest"

    run_in_container_as_root "mkdir -pv ${ETC_DIR} && chmod 777 -R ${ETC_DIR}"

    local init_packages=(
        'apollo-neo-buildtool'
        'apollo-neo-cyber'
        'apollo-neo-common'
        'apollo-neo-common-msgs'
    )
    run_in_container_as_root "apt update && apt install --only-upgrade -y ${init_packages[@]}"
}

determine_dev_image() {
    local repo="${APOLLO_ENV_CONTAINER_REPO:-${DOCKER_REPO}}"
    local tag="${CUSTOM_CONTAINER_TAG:-${APOLLO_ENV_CONTAINER_TAG:-${VERSION:-latest}}}"
    if [[ -z "${repo}" ]]; then
        if [[ "${TARGET_ARCH}" == "x86_64" ]]; then
            repo="${APOLLO_ENV_CONTAINER_REPO_X86}"
        elif [[ "${TARGET_ARCH}" == "aarch64" ]]; then
            repo="${APOLLO_ENV_CONTAINER_REPO_ARM}"
        else
            error "Unknown TARGET_ARCH: ${TARGET_ARCH}"
            exit 1
        fi
    fi
    APOLLO_ENV_CONTAINER_IMAGE="${repo}:${tag}"
}

check_host_environment() {
    if [[ "${HOST_OS}" != "Linux" ]]; then
        warning "Running Apollo dev container on ${HOST_OS} is UNTESTED, exiting..."
        exit 1
    fi
}

check_target_arch() {
    local arch="${TARGET_ARCH}"
    local support_arch=""
    for ent in "${SUPPORTED_ARCHS[@]}"; do
        support_arch="$support_arch $ent"
        if [[ "${ent}" == "${TARGET_ARCH}" ]]; then
            return 0
        fi
    done
    error "Unsupported target architecture: ${TARGET_ARCH}."
    error "Current Apollo support architecture:$support_arch."
    exit 1
}

setup_device() {
    if [ "$(uname -s)" != "Linux" ]; then
        info "Not on Linux, skip mapping devices."
        return
    fi
    if [[ "${TARGET_ARCH}" == "x86_64" ]]; then
        setup_device_for_amd64
    else
        setup_device_for_aarch64
    fi
}

setup_device_for_aarch64() {
    local can_dev="/dev/can0"
    local socket_can_dev="can0"
    if [ ! -e "${can_dev}" ]; then
        warning "No CAN device named ${can_dev}. "
    fi

    if [[ -x "$(command -v ip)" ]]; then
        if ! ip link show type can | grep "${socket_can_dev}" &>/dev/null; then
            warning "No SocketCAN device named ${socket_can_dev}."
        else
            sudo modprobe can
            sudo modprobe can_raw
            sudo modprobe mttcan
            sudo ip link set "${socket_can_dev}" type can bitrate 500000 sjw 4 berr-reporting on loopback off
            sudo ip link set up "${socket_can_dev}"
        fi
    else
        warning "ip command not found."
    fi
}

setup_device_for_amd64() {
    # setup CAN device
    local NUM_PORTS=8
    for i in $(seq 0 $((${NUM_PORTS} - 1))); do
        if [[ -e /dev/can${i} ]]; then
            continue
        elif [[ -e /dev/zynq_can${i} ]]; then
            # soft link if sensorbox exist
            sudo ln -s /dev/zynq_can${i} /dev/can${i}
        else
            break
            # sudo mknod --mode=a+rw /dev/can${i} c 52 ${i}
        fi
    done

    # Check Nvidia device
    if [[ ! -e /dev/nvidia0 ]]; then
        warning "No device named /dev/nvidia0"
    fi
    if [[ ! -e /dev/nvidiactl ]]; then
        warning "No device named /dev/nvidiactl"
    fi
    if [[ ! -e /dev/nvidia-uvm ]]; then
        warning "No device named /dev/nvidia-uvm"
    fi
    if [[ ! -e /dev/nvidia-uvm-tools ]]; then
        warning "No device named /dev/nvidia-uvm-tools"
    fi
    if [[ ! -e /dev/nvidia-modeset ]]; then
        warning "No device named /dev/nvidia-modeset"
    fi
}

setup_env_volumes() {
    local volumes=""

    for x in apollo opt; do
        local vol="${DEV_CONTAINER}_${x}"
        volumes="${volumes} -v ${vol}:/${x}"
    done

    volumes="$(tr -s " " <<<"${volumes}")"
    echo "${volumes}"
}

setup_devices_and_mount_local_volumes() {
    local __retval="$1"
    local user=${USER}
    local home_path
    local src_path

    if [ ${user} == "root" ]; then
        home_path="/root"
    else
        home_path="/home/${user}"
    fi

    src_path="${home_path}/.apollo"
    if [[ ! -d "${src_path}" ]]; then
        mkdir -p ${src_path}
    else
        if find ${src_path} ! -user ${user} -print | grep -q .; then
            warning "The user of ${src_path} is not ${user}, fixing ownership."
            # fix the permission issue inside container
            sudo chown -R ${user}:${user} ${src_path}
        fi
    fi
    volumes="${volumes} -v ${src_path}:${src_path}"

    setup_device

    local os_release="$(lsb_release -rs)"
    case "${os_release}" in
        16.04)
            warning "[Deprecated] Support for Ubuntu 16.04 will be removed" \
                "in the near future. Please upgrade to ubuntu 18.04+."
            volumes="${volumes} -v /dev:/dev"
            ;;
        18.04 | 20.04 | *)
            volumes="${volumes} -v /dev:/dev"
            ;;
    esac
    # local tegra_dir="/usr/lib/aarch64-linux-gnu/tegra"
    # if [[ "${TARGET_ARCH}" == "aarch64" && -d "${tegra_dir}" ]]; then
    #    volumes="${volumes} -v ${tegra_dir}:${tegra_dir}:ro"
    # fi
    volumes="${volumes} -v /media:/media \
                        -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
                        -v /etc/localtime:/etc/localtime:ro \
                        -v /usr/src:/usr/src \
                        -v /lib/modules:/lib/modules"
    volumes="$(tr -s " " <<<"${volumes}")"
    eval "${__retval}='${volumes}'"
}

docker_restart_volume() {
    local volume="$1"
    local image="$2"
    local path="$3"
    info "Create volume ${volume} from image: ${image}"
    docker_pull "${image}"
    docker volume rm "${volume}" >/dev/null 2>&1
    docker run -v "${volume}":"${path}" --rm "${image}" true >/dev/null
}

docker_pull() {
    local img="$1"
    if [[ "${USE_LOCAL_IMAGE}" -gt 0 ]]; then
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "${img}"; then
            info "Local image ${img} found and will be used."
            return
        fi
        warning "Image ${img} not found locally although local mode enabled. Trying to pull from remote registry."
    fi
    if [[ -n "${GEO_REGISTRY}" ]]; then
        img="${GEO_REGISTRY}/${img}"
    fi

    info "Start pulling docker image ${img} ..."
    if ! docker pull "${img}"; then
        error "Failed to pull docker image : ${img}"
        exit 1
    fi
}

determine_gpu_use_host() {
    # if gpu mode not specified, try to detect automatically
    if [[ -z "${USE_GPU_HOST}" ]]; then
        if [[ "${TARGET_ARCH}" == "aarch64" ]]; then
            if lsmod | grep -q "^nvgpu"; then
                USE_GPU_HOST=1
            else
                USE_GPU_HOST=0
            fi
        elif [[ "${TARGET_ARCH}" == "x86_64" ]]; then
            if [[ ! -x "$(command -v nvidia-smi)" ]]; then
                warning "No nvidia-smi found. CPU will be used"
                USE_GPU_HOST=0
            elif [[ -z "$(nvidia-smi)" ]]; then
                warning "No GPU device found. CPU will be used."
                USE_GPU_HOST=0
            else
                USE_GPU_HOST=1
            fi
        else
            error "Unsupported CPU architecture: ${TARGET_ARCH}"
            exit 1
        fi
    fi

    local nv_docker_doc="https://github.com/NVIDIA/nvidia-docker/blob/master/README.md"
    if [[ "${USE_GPU_HOST}" -eq 1 ]]; then
        if [[ -x "$(which nvidia-container-toolkit)" ]]; then
            local docker_version
            docker_version="$(docker version --format '{{.Server.Version}}')"
            if [[ "$(cmp_version "${docker_version}" "19.03")" -ge 0 ]]; then
                if [[ "${TARGET_ARCH}" == "aarch64" ]]; then
                    DOCKER_RUN_CMD="docker run --runtime nvidia"
                else
                    DOCKER_RUN_CMD="docker run --gpus all"
                fi
            else
                warning "Please upgrade to docker-ce 19.03+ to access GPU from container."
                USE_GPU_HOST=0
            fi
        elif [[ -x "$(which nvidia-container-runtime)" ]]; then
            if [[ "${TARGET_ARCH}" == "aarch64" ]]; then
                DOCKER_RUN_CMD="docker run --runtime nvidia"
            else
                DOCKER_RUN_CMD="docker run --gpus all"
            fi
        elif [[ -x "$(which nvidia-docker)" ]]; then
            DOCKER_RUN_CMD="nvidia-docker run"
        else
            USE_GPU_HOST=0
            warning "Cannot access GPU from within container. Please install latest Docker" \
                "and NVIDIA Container Toolkit as described by: "
            warning "  ${nv_docker_doc}"
        fi
    fi
}

remove_container_if_exists() {
    local container="$1"
    if docker ps -a --format '{{.Names}}' | grep -q "${container}"; then
        info "Removing existing Apollo container: ${container}"
        docker stop "${container}" >/dev/null
        docker rm -v -f "${container}" 2>/dev/null
    fi
}

check_can_restart() {
    if [[ ${FORCE_RECREATE_CONTAINER} -eq 1 ]]; then
        return
    else
        if docker_container_running "${DEV_CONTAINER}"; then
            ok "${DEV_CONTAINER} is still running, please run the following command:"
            ok "    aem enter"
            ok "Enjoy!"
            exit 0
        elif docker_container_stopped "${DEV_CONTAINER}"; then
            info "${DEV_CONTAINER} is down, try to restart."
            docker restart "${DEV_CONTAINER}"
            if [[ $? != 0 ]]; then
                error "restart ${DEV_CONTAINER} failed"
                error "if you want a new container, please run the following command:"
                error " aem start -f"
                exit -1
            else
                ok "${DEV_CONTAINER} successfully restart, please run the following command:"
                ok "    aem enter"
                ok "Enjoy!"
                exit 0
            fi
        fi
    fi
}

run_container() {
    local local_volumes=
    setup_devices_and_mount_local_volumes local_volumes

    local env_volumes="$(setup_env_volumes)"

    local extra_volumes="$(setup_extra_volumes)"

    info "Starting Docker container \"${DEV_CONTAINER}\" ..."

    local local_host="$(hostname)"
    local display="${DISPLAY:-:0}"
    local user="${CUSTOM_USER-$USER}"
    local uid="${CUSTOM_UID-$(id -u)}"
    local group="${CUSTOM_GROUP-$(id -g -n)}"
    local gid="${CUSTOM_GID-$(id -g)}"

    # passthrough all APOLLO_ENV_* variables
    local envs=()
    for x in ${!APOLLO_ENV_@}; do
        envs[${#envs[@]}]="-e ${x}=${!x}"
    done

    set -x

    ${DOCKER_RUN_CMD} -itd \
        --privileged \
        --name "${DEV_CONTAINER}" \
        --label "owner=${USER}" \
        -e DISPLAY="${display}" \
        -e CROSS_PLATFORM="${CROSS_PLATFORM_FLAG}" \
        -e DOCKER_USER="${user}" \
        -e USER="${user}" \
        -e DOCKER_USER_ID="${uid}" \
        -e HISTFILE=${APOLLO_ENV_WORKROOT}/.cache/.bash_history \
        -e DOCKER_GRP="${group}" \
        -e DOCKER_GRP_ID="${gid}" \
        -e DOCKER_IMG="${APOLLO_ENV_CONTAINER_IMAGE}" \
        -e USE_GPU_HOST="${USE_GPU_HOST}" \
        -e NVIDIA_VISIBLE_DEVICES=all \
        -e NVIDIA_DRIVER_CAPABILITIES=compute,video,graphics,utility \
        ${envs[@]} \
        ${local_volumes} \
        ${env_volumes} \
        ${extra_volumes} \
        --net host \
        -w ${APOLLO_ENV_WORKROOT} \
        --add-host "${DEV_INSIDE}:127.0.0.1" \
        --add-host "${local_host}:127.0.0.1" \
        --hostname "${DEV_INSIDE}" \
        --shm-size "${SHM_SIZE}" \
        --pid=host \
        -v /dev/null:/dev/raw1394 \
        "${APOLLO_ENV_CONTAINER_IMAGE}" \
        /bin/bash
}

create_envhome() {
    local envhome="${APOLLO_ENVS_ROOT}/${DEV_CONTAINER}"
    if [[ "${APOLLO_ENV_WORKLOCAL}" == "1" ]]; then
        envhome="${APOLLO_ENV_WORKSPACE}/.aem"
    fi
    local envroot="${envhome}/envroot"
    if [ ! -e "${envhome}" ]; then
        mkdir -p "${envhome}"
    fi
    if [ ! -e "${envroot}" ]; then
        mkdir -p ${envroot}/{apollo,etc,bin,lib,usr,opt}
    elif [ ! -d "${envroot}" ]; then
        warning "${envroot} already exists but is not a directory, recreate it."
        rm -rf "${envroot}"
        mkdir -p ${envroot}/{apollo,etc,bin,lib,usr,opt}
    fi

    for x in apollo opt; do
        local volume="${DEV_CONTAINER}_${x}"
        if ! docker_volume_exists "${volume}"; then
            docker volume create \
                --driver local \
                --opt type=none \
                --opt device=${envroot}/${x} \
                --opt o=bind \
                "${volume}"
        fi
    done

    if [[ "${APOLLO_ENV_WORKLOCAL}" == "0" ]]; then
        # link env volumes to workspace
        mkdir -p "${APOLLO_ENV_WORKSPACE}/.aem"
        if [[ -L "${APOLLO_ENV_WORKSPACE}/.aem/envroot" ]]; then
            rm -f "${APOLLO_ENV_WORKSPACE}/.aem/envroot"
        fi
        ln -s "${envroot}" "${APOLLO_ENV_WORKSPACE}/.aem/envroot"
    fi
}

start() {
    if [[ "${USER_AGREED}" != "yes" ]]; then
        check_agreement
    fi

    create_envhome

    info "Determine whether host GPU is available ..."
    determine_gpu_use_host
    info "USE_GPU_HOST: ${USE_GPU_HOST}"

    determine_dev_image

    if ! docker_pull "${APOLLO_ENV_CONTAINER_IMAGE}"; then
        error "Failed to pull docker image ${APOLLO_ENV_CONTAINER_IMAGE}"
        exit 1
    fi

    check_can_restart

    info "Remove existing Apollo Development container ..."
    remove_container_if_exists ${DEV_CONTAINER}

    run_container

    if [ $? -ne 0 ]; then
        if [[ "${USE_GPU_HOST}" -eq 1 ]]; then
            warning "Failed to start docker gpu container \"${DEV_CONTAINER}\" based on image: ${APOLLO_ENV_CONTAINER_IMAGE}"
            warning "It may caused by your incorrect drivers installation"
            info "Try to run in cpu mode"
            DOCKER_RUN_CMD="docker run"
            run_container

            if [ $? -ne 0 ]; then
                error "Failed to start docker container \"${DEV_CONTAINER}\" based on image: ${APOLLO_ENV_CONTAINER_IMAGE}"
                exit 1
            fi
        else
            error "Failed to start docker container \"${DEV_CONTAINER}\" based on image: ${APOLLO_ENV_CONTAINER_IMAGE}"
            exit 1
        fi
    fi
    set +x

    postrun_link_aem_and_install_core_pkgs
    postrun_start_user "${DEV_CONTAINER}"
    postrun_cross_platfrom_download "${DEV_CONTAINER}" "${CROSS_PLATFORM_FLAG}"

    ok "Congratulations! You have successfully finished setting up Apollo Dev Environment."
    ok "To login into the newly created ${DEV_CONTAINER} container, please run the following command:"
    ok "  aem enter"
    ok "Enjoy!"
}

main() {
    check_host_environment
    check_target_arch

    parse_arguments "$@"

    start
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Being sourced, do nothing
    :
else
    main "$@"
fi
