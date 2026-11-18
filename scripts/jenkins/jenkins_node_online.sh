#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
    echo "usage: $0 [node-name]" >&2
    exit 64
fi

JENKINS_BASE_URL=${JENKINS_BASE_URL:?JENKINS_BASE_URL is required}
JENKINS_BASE_URL=${JENKINS_BASE_URL%/}
PYTHON_BIN=${PYTHON_BIN:-python3}
JENKINS_USER=${JENKINS_USER:-}
JENKINS_TOKEN=${JENKINS_TOKEN:-}
STATE_DIR=${JENKINS_NODE_ONLINE_STATE_DIR:-/tmp/jenkins_node_online.d}

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

sanitize_state_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

register_state_file() {
    local node_name=$1
    local state_name
    local state_file

    mkdir -p "${STATE_DIR}"
    state_name=$(sanitize_state_name "${node_name}")
    state_file="${STATE_DIR}/${state_name}.state"
    rm -f "${state_file}" "${STATE_DIR}/${state_name}.done"
    printf 'NODE_NAME=%s\n' "${node_name}" >"${state_file}"
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

# One POST, no retry: toggleOffline is not idempotent, so the caller decides
# whether to send again by re-reading the node status.
post_url() {
    local url=$1
    local crumb_field=$2
    local crumb_value=$3

    curl_auth -sS -L --fail --connect-timeout 10 --max-time 30 \
        -H "${crumb_field}: ${crumb_value}" \
        -X POST \
        --data '' \
        "${url}" >/dev/null
}

state_value() {
    local state_file=$1
    local name=$2

    sed -n "s/^${name}=//p" "${state_file}" | tail -n 1
}

node_status() {
    local node_name=$1
    local node_api="${JENKINS_BASE_URL}/computer/${node_name}/api/json"

    fetch_url "${node_api}" | "${PYTHON_BIN}" -c '
import json, sys
data = json.load(sys.stdin)
print("true" if data.get("offline") else "false")
print("true" if data.get("temporarilyOffline") else "false")
print(data.get("offlineCauseReason") or "")
'
}

crumb_info() {
    fetch_url "${JENKINS_BASE_URL}/crumbIssuer/api/json" | "${PYTHON_BIN}" -c '
import json, sys
data = json.load(sys.stdin)
print(data["crumbRequestField"])
print(data["crumb"])
'
}

bring_node_online() {
    local node_name=$1
    local node_api="${JENKINS_BASE_URL}/computer/${node_name}/api/json"
    local status
    local offline
    local temporarily_offline
    local reason
    local crumb
    local crumb_field
    local crumb_value
    local attempt

    if [[ -z ${node_name} ]]; then
        echo "NODE_NAME is required" >&2
        return 64
    fi

    # toggleOffline flips the mark, so it is only sent when the node is known
    # to be marked temporarily offline. An unreadable status is never a reason
    # to toggle: that would take a healthy node offline.
    if ! status=$(node_status "${node_name}"); then
        echo "cannot read status of ${node_name}; not toggling" >&2
        return 1
    fi
    offline=$(printf '%s\n' "${status}" | sed -n '1p')
    temporarily_offline=$(printf '%s\n' "${status}" | sed -n '2p')
    reason=$(printf '%s\n' "${status}" | sed -n '3p')
    if [[ ! ${offline} =~ ^(true|false)$ || ! ${temporarily_offline} =~ ^(true|false)$ ]]; then
        echo "unexpected status for ${node_name}; not toggling" >&2
        return 1
    fi

    if [[ ${temporarily_offline} == "false" ]]; then
        if [[ ${offline} == "false" ]]; then
            echo "NODE_STATUS=${node_name} already_online"
            return 0
        fi
        # Offline without the mark: the agent is disconnected. Toggling would
        # only add a temporary-offline mark on top of that.
        echo "NODE_STATUS=${node_name} disconnected (agent not connected; nothing to toggle)" >&2
        return 1
    fi

    if ! crumb=$(crumb_info); then
        echo "cannot get a crumb; ${node_name} left as it is" >&2
        return 1
    fi
    crumb_field=$(printf '%s\n' "${crumb}" | sed -n '1p')
    crumb_value=$(printf '%s\n' "${crumb}" | sed -n '2p')

    # The HTTP reply does not tell whether the toggle was applied (a lost or
    # failed reply can follow an applied toggle), so the node status decides.
    # Another toggle is sent only while the node is still marked offline.
    for attempt in 1 2 3; do
        post_url "${JENKINS_BASE_URL}/computer/${node_name}/toggleOffline" "${crumb_field}" "${crumb_value}" ||
            echo "toggle request for ${node_name} reported an error (attempt ${attempt}/3); checking the node" >&2

        if ! status=$(node_status "${node_name}"); then
            echo "toggle sent, but the status of ${node_name} could not be re-read; not sending again" >&2
            return 1
        fi
        offline=$(printf '%s\n' "${status}" | sed -n '1p')
        temporarily_offline=$(printf '%s\n' "${status}" | sed -n '2p')
        [[ ${temporarily_offline} == "true" ]] || break
        [[ ${attempt} -lt 3 ]] && sleep 5
    done

    if [[ ${offline} == "false" && ${temporarily_offline} == "false" ]]; then
        echo "NODE_STATUS=${node_name} online"
        return 0
    fi

    echo "failed to bring ${node_name} online (reason=${reason})" >&2
    return 1
}

bring_state_nodes_online() {
    local failed=0

    mkdir -p "${STATE_DIR}"
    rm -f "${STATE_DIR}"/*.done
    shopt -s nullglob
    state_files=("${STATE_DIR}"/*.state)
    if [[ ${#state_files[@]} -eq 0 ]]; then
        echo "no Jenkins node online state files found in ${STATE_DIR}" >&2
        echo "write one .state file per node with NODE_NAME=<node>" >&2
        exit 64
    fi

    for state_file in "${state_files[@]}"; do
        node_name=$(state_value "${state_file}" NODE_NAME)
        if [[ -z ${node_name} ]]; then
            echo "skip invalid state file: ${state_file}" >&2
            failed=1
            continue
        fi

        if bring_node_online "${node_name}"; then
            mv "${state_file}" "${state_file%.state}.done"
        else
            failed=1
        fi
    done

    return "${failed}"
}

if [[ $# -eq 0 ]]; then
    bring_state_nodes_online
else
    register_state_file "$1"
    bring_node_online "$1" || exit 1
    # Done: take it out of the pending queue so a later run does not replay it.
    state_file="${STATE_DIR}/$(sanitize_state_name "$1").state"
    [[ -f ${state_file} ]] && mv "${state_file}" "${state_file%.state}.done"
    exit 0
fi
