#!/bin/sh
set -eu

# Seed writable runtime config (ADR-070 / apme#498). Helm uses the same pattern:
# copy seed config once, then allow Portal HTTP admin to persist providers.
CONFIG_ROOT="${XDG_CONFIG_HOME:-/var/abbenay-config}"
CONFIG_DIR="${CONFIG_ROOT}/abbenay"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SEED_FILE="/seed/config.yaml"
LOG_FILE="${ABBENAY_ENTRYPOINT_LOG:-/tmp/abbenay-entrypoint.log}"

mkdir -p "${CONFIG_DIR}"
if [ ! -f "${CONFIG_FILE}" ]; then
  if [ -f "${SEED_FILE}" ]; then
    cp "${SEED_FILE}" "${CONFIG_FILE}"
  else
    echo "ERROR: missing Abbenay seed config at ${SEED_FILE}" >&2
    exit 1
  fi
fi

SECRETS_FILE="/var/abbenay-secrets/providers.env"
# Debounce reloads so atomic writes + configure HTTP are not killed mid-flight.
RELOAD_SETTLE_SECS="${ABBENAY_SECRETS_RELOAD_SETTLE_SECS:-3}"

# Load KEY="value" lines without shell evaluation (never `.` / source the file).
# Only ABBENAY_PROVIDER_* keys are exported.
load_secrets() {
  if [ ! -f "${SECRETS_FILE}" ]; then
    return 0
  fi
  # Clear previously exported provider keys so deletions take effect.
  # shellcheck disable=SC2046
  for _k in $(env | sed -n 's/^\(ABBENAY_PROVIDER_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "${_k}" || true
  done
  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      ''|'#'*) continue ;;
    esac
    key=${line%%=*}
    val=${line#*=}
    case "${key}" in
      ABBENAY_PROVIDER_[A-Za-z0-9_]*) ;;
      *) continue ;;
    esac
    case "${val}" in
      \"*\")
        val=${val#\"}
        val=${val%\"}
        # Unescape \" and \\ written by Portal serializeEnvFile.
        val=$(printf '%s' "${val}" | sed 's/\\"/"/g; s/\\\\/\\/g')
        ;;
      \'*\')
        val=${val#\'}
        val=${val%\'}
        ;;
    esac
    # Parameter expansion only — command substitution inside val is NOT re-scanned.
    export "${key}=${val}"
  done < "${SECRETS_FILE}"
}

# Must run in the main shell (not command substitution) so $! stays a real child
# and wait/kill work. Otherwise: "wait: pid N is not a child of this shell".
start_abbenay() {
  load_secrets
  # Drop stale runtime after SIGKILL/restart so abbenay does not attach to a dead sock.
  runtime_dir="${XDG_RUNTIME_DIR:-/tmp/abbenay-run}"
  rm -rf "${runtime_dir}/abbenay" 2>/dev/null || true
  mkdir -p "${runtime_dir}"
  # Abbenay prints daemon status to stdout — redirect so $! capture stays reliable.
  /opt/abbenay/abbenay "$@" >>"${LOG_FILE}" 2>&1 &
  abbenay_pid=$!
}

secrets_mtime() {
  if [ -f "${SECRETS_FILE}" ]; then
    stat -c %Y "${SECRETS_FILE}" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Always watch: cold start without providers.env must pick up the first Portal write.
last_mtime=$(secrets_mtime)
while true; do
  start_abbenay "$@"
  pid=${abbenay_pid}
  while kill -0 "${pid}" 2>/dev/null; do
    sleep 2
    cur_mtime=$(secrets_mtime)
    if [ "${cur_mtime}" != "${last_mtime}" ]; then
      sleep "${RELOAD_SETTLE_SECS}"
      cur_mtime=$(secrets_mtime)
      last_mtime="${cur_mtime}"
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      break
    fi
  done
  if ! kill -0 "${pid}" 2>/dev/null; then
    status=0
    wait "${pid}" || status=$?
    exit "${status}"
  fi
done
