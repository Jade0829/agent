#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <node-name> [node-name ...]" >&2
    exit 64
fi

STATE_DIR=${JENKINS_NODE_ONLINE_STATE_DIR:-/tmp/jenkins_node_online.d}

sanitize_state_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

mkdir -p "${STATE_DIR}"

for node_name in "$@"; do
    state_name=$(sanitize_state_name "${node_name}")
    state_file="${STATE_DIR}/${state_name}.state"
    rm -f "${state_file}" "${STATE_DIR}/${state_name}.done"
    printf 'NODE_NAME=%s\n' "${node_name}" >"${state_file}"
    echo "STATE_FILE=${state_file}"
done
