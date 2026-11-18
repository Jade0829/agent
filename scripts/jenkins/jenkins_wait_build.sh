#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 1 || $# -gt 5 ]]; then
    echo "usage: $0 [<job-name> <build-number> [initial-wait-sec] [interval-sec] [timeout-sec]]" >&2
    exit 64
fi

JENKINS_BASE_URL=${JENKINS_BASE_URL:?JENKINS_BASE_URL is required}
JENKINS_BASE_URL=${JENKINS_BASE_URL%/}
PYTHON_BIN=${PYTHON_BIN:-python3}
JENKINS_USER=${JENKINS_USER:-}
JENKINS_TOKEN=${JENKINS_TOKEN:-}
STATE_DIR=${JENKINS_WAIT_STATE_DIR:-/tmp/jenkins_wait_build.d}

if [[ -z ${JENKINS_USER} || -z ${JENKINS_TOKEN} ]]; then
    echo "JENKINS_USER and JENKINS_TOKEN are required" >&2
    exit 64
fi

auth=("${JENKINS_USER}:${JENKINS_TOKEN}")

sanitize_state_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

register_state_file() {
    local job_name=$1
    local build_number=$2
    local initial_wait=${3:-}
    local interval=${4:-}
    local timeout=${5:-}
    local state_name
    local state_file

    mkdir -p "${STATE_DIR}"
    state_name=$(sanitize_state_name "${job_name}-${build_number}")
    state_file="${STATE_DIR}/${state_name}.state"
    rm -f "${state_file}" "${STATE_DIR}/${state_name}.done"
    {
        printf 'JOB_NAME=%s\n' "${job_name}"
        printf 'BUILD_NUMBER=%s\n' "${build_number}"
        [[ -n ${initial_wait} ]] && printf 'INITIAL_WAIT=%s\n' "${initial_wait}"
        [[ -n ${interval} ]] && printf 'INTERVAL=%s\n' "${interval}"
        [[ -n ${timeout} ]] && printf 'TIMEOUT=%s\n' "${timeout}"
    } >"${state_file}"
    echo "STATE_FILE=${state_file}"
}

fetch_url() {
    local url=$1
    local attempt

    for attempt in 1 2 3; do
        if curl -sS -L --fail --connect-timeout 10 --max-time 30 -u "${auth[0]}" "${url}"; then
            return 0
        fi
        echo "curl failed for ${url} (attempt ${attempt}/3)" >&2
        sleep 5
    done

    return 1
}

state_value() {
    local state_file=$1
    local name=$2

    sed -n "s/^${name}=//p" "${state_file}" | tail -n 1
}

build_status() {
    local job_name=$1
    local build_number=$2
    local build_api="${JENKINS_BASE_URL}/job/${job_name}/${build_number}/api/json"

    fetch_url "${build_api}" | "${PYTHON_BIN}" -c '
import json, sys
data = json.load(sys.stdin)
print(data.get("result") or "null")
print("true" if data.get("building") else "false")
'
}

workflow_node() {
    local job_name=$1
    local build_number=$2
    local console_url="${JENKINS_BASE_URL}/job/${job_name}/${build_number}/consoleText"

    fetch_url "${console_url}" |
        grep -oE 'Running on [^ ]+' |
        tail -n 1 |
        awk '{print $3}'
}

monitor_single_build() {
    local job_name=$1
    local build_number=$2
    local initial_wait=${3:-300}
    local interval=${4:-60}
    local timeout=${5:-1800}
    local start_epoch
    local slept_initial_wait=false

    if [[ -z ${job_name} || -z ${build_number} ]]; then
        echo "JOB_NAME and BUILD_NUMBER are required" >&2
        exit 64
    fi

    echo "monitor build ${job_name} #${build_number}"
    start_epoch=$(date +%s)

    while true; do
        status=$(build_status "${job_name}" "${build_number}")
        result=$(printf '%s\n' "${status}" | sed -n '1p')
        building=$(printf '%s\n' "${status}" | sed -n '2p')
        echo "$(date '+%F %T') ${job_name} #${build_number} result=${result} building=${building}"

        if [[ ${building} == "false" && ${result} != "null" ]]; then
            node=$(workflow_node "${job_name}" "${build_number}" || true)
            echo "BUILD_RESULT=${result}"
            echo "WORKFLOW_NODE=${node:-unknown}"
            return 0
        fi

        if (( $(date +%s) - start_epoch >= timeout )); then
            echo "timeout waiting for ${job_name} #${build_number}" >&2
            return 124
        fi

        if [[ ${slept_initial_wait} == "false" ]]; then
            echo "$(date '+%F %T') next check in ${initial_wait}s"
            sleep "${initial_wait}"
            slept_initial_wait=true
        else
            echo "$(date '+%F %T') next check in ${interval}s"
            sleep "${interval}"
        fi
    done
}

monitor_state_dir() {
    local interval=60
    local timeout=1800
    local start_epoch

    mkdir -p "${STATE_DIR}"
    rm -f "${STATE_DIR}"/*.done
    shopt -s nullglob
    state_files=("${STATE_DIR}"/*.state)
    if [[ ${#state_files[@]} -eq 0 ]]; then
        echo "no Jenkins wait state files found in ${STATE_DIR}" >&2
        echo "write one .state file per build with JOB_NAME=<job> and BUILD_NUMBER=<number>" >&2
        exit 64
    fi

    echo "monitor state directory ${STATE_DIR}"
    start_epoch=$(date +%s)

    while true; do
        local remaining=0
        state_files=("${STATE_DIR}"/*.state)
        if [[ ${#state_files[@]} -eq 0 ]]; then
            echo "all tracked builds completed"
            return 0
        fi

        for state_file in "${state_files[@]}"; do
            job_name=$(state_value "${state_file}" JOB_NAME)
            build_number=$(state_value "${state_file}" BUILD_NUMBER)
            if [[ -z ${job_name} || -z ${build_number} ]]; then
                echo "skip invalid state file: ${state_file}" >&2
                continue
            fi

            if ! status=$(build_status "${job_name}" "${build_number}"); then
                echo "status fetch failed for ${job_name} #${build_number}; will retry" >&2
                remaining=1
                continue
            fi
            result=$(printf '%s\n' "${status}" | sed -n '1p')
            building=$(printf '%s\n' "${status}" | sed -n '2p')
            echo "$(date '+%F %T') ${job_name} #${build_number} result=${result} building=${building}"

            if [[ ${building} == "false" && ${result} != "null" ]]; then
                node=$(workflow_node "${job_name}" "${build_number}" || true)
                echo "BUILD_RESULT ${job_name} #${build_number}=${result}"
                echo "WORKFLOW_NODE ${job_name} #${build_number}=${node:-unknown}"
                mv "${state_file}" "${state_file%.state}.done"
            else
                remaining=1
            fi
        done

        if [[ ${remaining} -eq 0 ]]; then
            echo "all tracked builds completed"
            return 0
        fi

        if (( $(date +%s) - start_epoch >= timeout )); then
            echo "timeout waiting for tracked Jenkins builds" >&2
            return 124
        fi

        echo "$(date '+%F %T') next check in ${interval}s"
        sleep "${interval}"
    done
}

if [[ $# -eq 0 ]]; then
    monitor_state_dir
else
    register_state_file "$@"
    monitor_single_build "$@"
fi
