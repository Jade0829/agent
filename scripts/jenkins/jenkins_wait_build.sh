#!/usr/bin/env bash
# Wait for Jenkins builds to finish.
#   <job> <build> [initial-wait] [interval] [timeout]   wait for one build
#   (no arguments)                                       wait for every registered build
# A job inside folders is written as folder/sub/job.
# Exit code: 0 every build ended SUCCESS, 1 a build ended otherwise,
#            124 timeout (also when the status could not be read until the
#            timeout: wrong job name, Jenkins unreachable), 64 usage error.
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

if [[ ${JENKINS_USER}${JENKINS_TOKEN} == *[$'\n\r']* ]]; then
    echo "JENKINS_USER / JENKINS_TOKEN must not contain line breaks" >&2
    exit 64
fi

# curl with the credentials passed on stdin (-K -), so the token never shows
# up in the process list.
curl_auth() {
    local u=${JENKINS_USER//\\/\\\\} t=${JENKINS_TOKEN//\\/\\\\}
    printf 'user = "%s:%s"\n' "${u//\"/\\\"}" "${t//\"/\\\"}" | curl -K - "$@"
}

# job_path NAME: folder/sub/job -> /job/folder/job/sub/job/job, each part URL-encoded.
job_path() {
    "${PYTHON_BIN}" -c '
import os, sys, urllib.parse
print("".join("/job/" + urllib.parse.quote(os.fsencode(p), safe="") for p in sys.argv[1].split("/") if p))
' "$1"
}

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
        if curl_auth -sS -L --fail --connect-timeout 10 --max-time 30 "${url}"; then
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
    local build_api
    build_api="${JENKINS_BASE_URL}$(job_path "${job_name}")/${build_number}/api/json"

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
    local console_url
    console_url="${JENKINS_BASE_URL}$(job_path "${job_name}")/${build_number}/consoleText"

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
    local v

    if [[ -z ${job_name} || -z ${build_number} ]]; then
        echo "JOB_NAME and BUILD_NUMBER are required" >&2
        exit 64
    fi

    for v in "${initial_wait}" "${interval}" "${timeout}"; do
        if [[ ! ${v} =~ ^[0-9]+$ ]]; then
            echo "initial-wait, interval and timeout must be whole seconds: ${v}" >&2
            exit 64
        fi
    done

    echo "monitor build ${job_name} #${build_number}"
    start_epoch=$(date +%s)

    while true; do
        # An unreadable status is not a build result: keep trying until the timeout.
        if ! status=$(build_status "${job_name}" "${build_number}" 2>/dev/null); then
            echo "status fetch failed for ${job_name} #${build_number}; will retry" >&2
            if (( $(date +%s) - start_epoch >= 10#${timeout} )); then
                echo "timeout: status of ${job_name} #${build_number} never became readable" >&2
                return 124
            fi
            sleep "${interval}"
            continue
        fi
        result=$(printf '%s\n' "${status}" | sed -n '1p')
        building=$(printf '%s\n' "${status}" | sed -n '2p')
        echo "$(date '+%F %T') ${job_name} #${build_number} result=${result} building=${building}"

        if [[ ${building} == "false" && ${result} != "null" ]]; then
            node=$(workflow_node "${job_name}" "${build_number}" || true)
            echo "BUILD_RESULT=${result}"
            echo "WORKFLOW_NODE=${node:-unknown}"
            # This build is done: take it out of the pending queue.
            state_file="${STATE_DIR}/$(sanitize_state_name "${job_name}-${build_number}").state"
            [[ -f ${state_file} ]] && mv "${state_file}" "${state_file%.state}.done"
            [[ ${result} == "SUCCESS" ]] && return 0
            return 1
        fi

        if (( $(date +%s) - start_epoch >= 10#${timeout} )); then
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
    local initial_wait=''
    local start_epoch
    local failed=0
    local first_round=true
    local v

    mkdir -p "${STATE_DIR}"
    rm -f "${STATE_DIR}"/*.done
    shopt -s nullglob
    state_files=("${STATE_DIR}"/*.state)
    if [[ ${#state_files[@]} -eq 0 ]]; then
        echo "no Jenkins wait state files found in ${STATE_DIR}" >&2
        echo "write one .state file per build with JOB_NAME=<job> and BUILD_NUMBER=<number>" >&2
        exit 64
    fi

    # Timings recorded at registration: the shortest interval and initial wait,
    # the longest timeout.
    # A build registered without timings counts with the defaults (60s / 1800s),
    # so one short-lived entry cannot cut the wait for the others.
    local first=true
    for state_file in "${state_files[@]}"; do
        v=$(state_value "${state_file}" INTERVAL); [[ ${v} =~ ^[0-9]+$ ]] || v=60
        v=$((10#${v}))
        if [[ ${first} == true ]] || (( v < interval )); then interval=${v}; fi
        v=$(state_value "${state_file}" TIMEOUT); [[ ${v} =~ ^[0-9]+$ ]] || v=1800
        v=$((10#${v}))
        if [[ ${first} == true ]] || (( v > timeout )); then timeout=${v}; fi
        v=$(state_value "${state_file}" INITIAL_WAIT)
        if [[ ${v} =~ ^[0-9]+$ ]]; then
            v=$((10#${v}))
            if [[ -z ${initial_wait} ]] || (( v < initial_wait )); then initial_wait=${v}; fi
        fi
        first=false
    done

    echo "monitor state directory ${STATE_DIR} (interval=${interval}s timeout=${timeout}s)"
    start_epoch=$(date +%s)

    while true; do
        local remaining=0
        state_files=("${STATE_DIR}"/*.state)
        if [[ ${#state_files[@]} -eq 0 ]]; then
            echo "all tracked builds completed"
            return "${failed}"
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
                [[ ${result} == "SUCCESS" ]] || failed=1
                mv "${state_file}" "${state_file%.state}.done"
            else
                remaining=1
            fi
        done

        if [[ ${remaining} -eq 0 ]]; then
            echo "all tracked builds completed"
            return "${failed}"
        fi

        if (( $(date +%s) - start_epoch >= timeout )); then
            echo "timeout waiting for tracked Jenkins builds" >&2
            return 124
        fi

        if [[ ${first_round} == true && -n ${initial_wait} ]]; then
            echo "$(date '+%F %T') next check in ${initial_wait}s"
            sleep "${initial_wait}"
        else
            echo "$(date '+%F %T') next check in ${interval}s"
            sleep "${interval}"
        fi
        first_round=false
    done
}

if [[ $# -eq 0 ]]; then
    monitor_state_dir
else
    register_state_file "$@"
    monitor_single_build "$@"
fi
