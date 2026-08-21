#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
SOURCE_ROOT="$(cd "${SCRIPT_DIRECTORY}/../.." && pwd -P)"
readonly SOURCE_ROOT
TEST_ROOT="$(cd "$(mktemp -d)" && pwd -P)"
readonly TEST_ROOT
trap 'rm -rf "${TEST_ROOT}"' EXIT

readonly TEST_REPOSITORY="${TEST_ROOT}/repository"
readonly FAKE_BIN="${TEST_ROOT}/bin"
export FAKE_DOCKER_STATE="${TEST_ROOT}/docker"
export SOLIDPDF_LINUX_PLATFORM="linux/arm64"

mkdir -p "${TEST_REPOSITORY}/Scripts" "${FAKE_BIN}" "${FAKE_DOCKER_STATE}"
cp "${SOURCE_ROOT}/Scripts/linux-container" "${TEST_REPOSITORY}/Scripts/linux-container"
cp "${SOURCE_ROOT}/Scripts/Tests/fake-docker" "${FAKE_BIN}/docker"
chmod +x "${TEST_REPOSITORY}/Scripts/linux-container" "${FAKE_BIN}/docker"
printf '{"pins":[]}\n' >"${TEST_REPOSITORY}/Package.resolved"
export PATH="${FAKE_BIN}:${PATH}"

function fail() {
  echo "linux-container-tests: $*" >&2
  exit 1
}

function expect_equal() {
  [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

function expect_exists() {
  [[ -e "$1" ]] || fail "expected $1 to exist"
}

function expect_absent() {
  [[ ! -e "$1" ]] || fail "expected $1 to be absent"
}

function creation_count() {
  grep -c '^created$' "${FAKE_DOCKER_STATE}/log" || true
}

function stable_name() {
  "${TEST_REPOSITORY}/Scripts/linux-container" status | awk '/^Container:/ {print $2}'
}

function create_legacy() {
  local name=$1
  local workspace=$2
  local platform=$3
  docker create --name "${name}" \
    --label com.solidpdf.role=swift-linux \
    --label "com.solidpdf.workspace=${workspace}" \
    --label "com.solidpdf.platform=${platform}" \
    swift:old sleep infinity >/dev/null
}

"${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
readonly CONTAINER_NAME="$(stable_name)"
readonly CONTAINER_DIRECTORY="${FAKE_DOCKER_STATE}/containers/${CONTAINER_NAME}"
expect_equal "$(creation_count)" 1
expect_equal "$(grep -c '^apt-get .*install' "${FAKE_DOCKER_STATE}/log")" 1
expect_exists "${CONTAINER_DIRECTORY}"

"${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
expect_equal "$(creation_count)" 1

docker stop "${CONTAINER_NAME}" >/dev/null
"${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
expect_equal "$(cat "${CONTAINER_DIRECTORY}/running")" true
expect_equal "$(creation_count)" 1

readonly ORIGINAL_MOUNTS="$(cat "${CONTAINER_DIRECTORY}/mounts")"
SOLIDPDF_LINUX_SWIFT_IMAGE=swift:6.3.3-jammy \
  "${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
expect_equal "$(creation_count)" 2
expect_equal "$(cat "${CONTAINER_DIRECTORY}/mounts")" "${ORIGINAL_MOUNTS}"

SOLIDPDF_LINUX_SWIFT_IMAGE=swift:6.3.3-jammy SOLIDPDF_LINUX_SCRIPT_SCHEMA_VERSION=8 \
  "${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
expect_equal "$(creation_count)" 3
expect_equal "$(cat "${CONTAINER_DIRECTORY}/mounts")" "${ORIGINAL_MOUNTS}"

create_legacy "solidpdf-swift-old-linux-arm64-fonts-pdf-v5-legacy" "${TEST_REPOSITORY}" linux/arm64
"${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
expect_absent "${FAKE_DOCKER_STATE}/containers/solidpdf-swift-old-linux-arm64-fonts-pdf-v5-legacy"

create_legacy "solidpdf-swift-active-linux-arm64-fonts-pdf-v5-legacy" "${TEST_REPOSITORY}" linux/arm64
echo 1 >"${FAKE_DOCKER_STATE}/containers/solidpdf-swift-active-linux-arm64-fonts-pdf-v5-legacy/exec-count"
if "${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null 2>&1; then
  fail "active legacy container should block migration"
fi
expect_exists "${FAKE_DOCKER_STATE}/containers/solidpdf-swift-active-linux-arm64-fonts-pdf-v5-legacy"
echo 0 >"${FAKE_DOCKER_STATE}/containers/solidpdf-swift-active-linux-arm64-fonts-pdf-v5-legacy/exec-count"
"${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null

create_legacy "solidpdf-swift-foreign-linux-arm64-fonts-pdf-v5-legacy" "${TEST_ROOT}/foreign" linux/arm64
create_legacy "solidpdf-swift-other-linux-amd64-fonts-pdf-v5-legacy" "${TEST_REPOSITORY}" linux/amd64
create_legacy "solidpdf-benchmark-linux-arm64-temporary" "${TEST_ROOT}/benchmark" linux/arm64
"${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
expect_exists "${FAKE_DOCKER_STATE}/containers/solidpdf-swift-foreign-linux-arm64-fonts-pdf-v5-legacy"
expect_exists "${FAKE_DOCKER_STATE}/containers/solidpdf-swift-other-linux-amd64-fonts-pdf-v5-legacy"
expect_exists "${FAKE_DOCKER_STATE}/containers/solidpdf-benchmark-linux-arm64-temporary"

printf '{"pins":[{"identity":"changed"}]}\n' >"${TEST_REPOSITORY}/Package.resolved"
"${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null
cmp "${TEST_REPOSITORY}/Package.resolved" \
  "${TEST_REPOSITORY}/.cache/linux-container/linux-arm64/Package.resolved"

"${TEST_REPOSITORY}/Scripts/linux-container" remove >/dev/null
readonly BEFORE_CONCURRENT_COUNT="$(creation_count)"
FAKE_DOCKER_CREATE_DELAY=0.2 "${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null &
first_pid=$!
FAKE_DOCKER_CREATE_DELAY=0.2 "${TEST_REPOSITORY}/Scripts/linux-container" ensure >/dev/null &
second_pid=$!
wait "${first_pid}"
wait "${second_pid}"
expect_equal "$(creation_count)" "$((BEFORE_CONCURRENT_COUNT + 1))"

if "${TEST_REPOSITORY}/Scripts/linux-container" exec false >/dev/null 2>&1; then
  fail "docker exec command failure should propagate"
fi

echo "linux-container lifecycle tests passed"
