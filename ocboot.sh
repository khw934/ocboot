#!/bin/bash

set -e

DEFAULT_REPO=registry.cn-beijing.aliyuncs.com/yunionio
IMAGE_REPOSITORY=${IMAGE_REPOSITORY:-$DEFAULT_REPO}
VERSION=${VERSION:-v4-k3s.4}
OCBOOT_IMAGE="$IMAGE_REPOSITORY/ocboot:$VERSION"

CUR_DIR="$(pwd)"
CONTAINER_NAME="buildah-ocboot"

ensure_buildah() {
    if ! [ -x "$(command -v buildah)" ]; then
        echo "Installing buildah ..."
        ./scripts/install-buildah.sh
    fi
}

buildah_from_image() {
    if buildah ps | grep $CONTAINER_NAME; then
        buildah rm $CONTAINER_NAME
    fi
    local img="$1"
    echo "Using buildah pull $img"
    buildah from --name $CONTAINER_NAME "$img"
}

ensure_buildah

buildah_from_image "$OCBOOT_IMAGE"

mkdir -p "$HOME/.ssh"

CMD=""

is_ocboot_subcmd() {
    local subcmds="install upgrade add-node add-lbagent backup restore setup-container-env"
    for subcmd in $subcmds; do
        if [[ "$1" == "$subcmd" ]]; then
            return 0
        fi
    done
    return 1
}

if is_ocboot_subcmd "$1"; then
    CMD="ocboot.py"
fi

buildah_version=$(buildah --version | awk '{print $3}')
buildah_version_major=$(echo "$buildah_version" | awk -F. '{print $1}')
buildah_version_minor=$(echo "$buildah_version" | awk -F. '{print $2}')

buildah_extra_args=()

# buildah accept --env since 1.23
echo "buildah version: $buildah_version"
if [[ $buildah_version_major -eq 1 ]] && [[ "$buildah_version_minor" -gt 23 ]]; then
    buildah_extra_args+=(-e ANSIBLE_VERBOSITY="${ANSIBLE_VERBOSITY:-0}")
fi

cmd_extra_args=""

if [[ "$1" == "run.py" ]]; then
    if [[ "$IMAGE_REPOSITORY" != "$DEFAULT_REPO" ]]; then
        cmd_extra_args="$cmd_extra_args -i $IMAGE_REPOSITORY"
    fi
fi

buildah run -t "${buildah_extra_args[@]}" \
    --net=host \
    -v "$HOME/.ssh:/root/.ssh" \
    -v "$(pwd):/ocboot" \
    -v "$(pwd)/airgap_assets/k3s-install.sh:/airgap_assets/k3s-install.sh:ro" \
    "$CONTAINER_NAME" $CMD "$@" $cmd_extra_args
