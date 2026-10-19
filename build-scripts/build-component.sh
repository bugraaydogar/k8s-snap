#!/bin/bash

set -ex

DIR=$(realpath "$(dirname "${0}")")
export BUILD_SCRIPTS_DIR="${DIR}"
source "${DIR}/lib.sh"

BUILD_DIRECTORY="${SNAPCRAFT_PART_BUILD:-${DIR}/.build}"
INSTALL_DIRECTORY="${SNAPCRAFT_PART_INSTALL:-${DIR}/.install}"

mkdir -p "${BUILD_DIRECTORY}" "${INSTALL_DIRECTORY}"

COMPONENT_NAME="${1}"
COMPONENT_DIRECTORY="${DIR}/components/${COMPONENT_NAME}"

GIT_REPOSITORY="$(cat "${COMPONENT_DIRECTORY}/repository")"
GIT_TAG="$(cat "${COMPONENT_DIRECTORY}/version")"

COMPONENT_BUILD_DIRECTORY="${BUILD_DIRECTORY}/${COMPONENT_NAME}"

is_git_commit_sha() {
  [[ "${1}" =~ ^[0-9a-fA-F]{40}$ ]]
}

checkout_git_commit_sha() {
  local repository="${1}" commit_sha="${2}" target_directory="${3}"
  local normalized_sha
  normalized_sha="$(echo "${commit_sha}" | tr '[:upper:]' '[:lower:]')"

  mkdir -p "${target_directory}"
  cd "${target_directory}"
  git init
  git remote add origin "${repository}"
  retry 5 5 git fetch --depth 1 origin "${commit_sha}"
  git checkout --detach FETCH_HEAD
  if [ "$(git rev-parse HEAD)" != "${normalized_sha}" ]; then
    echo "Fetched commit $(git rev-parse HEAD), expected ${normalized_sha}" >&2
    exit 1
  fi
}

# cleanup git repository if we cannot git checkout to the build tag
if [ -d "${COMPONENT_BUILD_DIRECTORY}" ]; then
  cd "${COMPONENT_BUILD_DIRECTORY}"
  if ! git reset --hard "${GIT_TAG}"; then
    cd "${BUILD_DIRECTORY}"
    rm -rf "${COMPONENT_BUILD_DIRECTORY}"
  fi
fi

if [ ! -d "${COMPONENT_BUILD_DIRECTORY}" ]; then
  if is_git_commit_sha "${GIT_TAG}"; then
    checkout_git_commit_sha "${GIT_REPOSITORY}" "${GIT_TAG}" "${COMPONENT_BUILD_DIRECTORY}"
  else
    retry 5 5 git clone "${GIT_REPOSITORY}" --depth 1 -b "${GIT_TAG}" "${COMPONENT_BUILD_DIRECTORY}"
  fi
fi

cd "${COMPONENT_BUILD_DIRECTORY}"
echo "Building ${COMPONENT_NAME} at commit $(git rev-parse HEAD)"
git config user.name "K8s builder bot"
git config user.email "k8s-bot@canonical.com"

if [ -e "${COMPONENT_DIRECTORY}/pre-patch.sh" ]; then
  bash -xe "${COMPONENT_DIRECTORY}/pre-patch.sh"
fi

for patch in $(python3 "${DIR}/print-patches-for.py" "${COMPONENT_NAME}" "${GIT_TAG}"); do
  git am "${patch}"
done

bash -xe "${COMPONENT_DIRECTORY}/build.sh" "${INSTALL_DIRECTORY}" "${GIT_TAG}"
