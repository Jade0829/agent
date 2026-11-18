#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 5 ]]; then
    echo "usage: $0 <job-name> <build-number> [initial-wait-sec] [interval-sec] [timeout-sec]" >&2
    exit 64
fi

JOB_NAME=$1
BUILD_NUMBER=$2
INITIAL_WAIT=${3:-}
INTERVAL=${4:-}
TIMEOUT=${5:-}
STATE_DIR=${JENKINS_WAIT_STATE_DIR:-/tmp/jenkins_wait_build.d}

# Readable prefix plus a checksum of the exact name, so two different names
# ("a/b" and "a_b") never share a state file.
sanitize_state_name() {
    printf '%s.%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')" "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
}

mkdir -p "${STATE_DIR}"
state_name=$(sanitize_state_name "${JOB_NAME}-${BUILD_NUMBER}")
state_file="${STATE_DIR}/${state_name}.state"

rm -f "${state_file}" "${STATE_DIR}/${state_name}.done"
{
    printf 'JOB_NAME=%s\n' "${JOB_NAME}"
    printf 'BUILD_NUMBER=%s\n' "${BUILD_NUMBER}"
    [[ -n ${INITIAL_WAIT} ]] && printf 'INITIAL_WAIT=%s\n' "${INITIAL_WAIT}"
    [[ -n ${INTERVAL} ]] && printf 'INTERVAL=%s\n' "${INTERVAL}"
    [[ -n ${TIMEOUT} ]] && printf 'TIMEOUT=%s\n' "${TIMEOUT}"
} >"${state_file}"

echo "STATE_FILE=${state_file}"
