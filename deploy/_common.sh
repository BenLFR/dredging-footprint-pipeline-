#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This file must be sourced, not executed."
  exit 2
fi

DEPLOY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_REPO_ROOT="$(cd "${DEPLOY_SCRIPT_DIR}/.." && pwd)"

deploy::info() {
  printf '[INFO] %s\n' "$*"
}

deploy::warn() {
  printf '[WARN] %s\n' "$*" >&2
}

deploy::error() {
  printf '[ERROR] %s\n' "$*" >&2
}

deploy::usage_error() {
  deploy::error "$1"
  exit 2
}

deploy::load_env() {
  local env_file="${1:-${DEPLOY_ENV_FILE:-${DEPLOY_SCRIPT_DIR}/config.env}}"

  if [[ -f "${env_file}" ]]; then
    # shellcheck disable=SC1090
    source "${env_file}"
  fi

  DEPLOY_ENV_FILE="${env_file}"
  export DEPLOY_ENV_FILE
}

deploy::require_commands() {
  local cmd=""
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      deploy::usage_error "Required command not found: ${cmd}"
    fi
  done
}

deploy::require_vars() {
  local missing=()
  local var_name=""

  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      missing+=("${var_name}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    deploy::usage_error "Missing required variable(s): ${missing[*]}"
  fi
}

deploy::ssh_target() {
  if [[ -n "${HPC_USER:-}" ]]; then
    printf '%s@%s' "${HPC_USER}" "${HPC_HOST}"
  else
    printf '%s' "${HPC_HOST}"
  fi
}

deploy::run_ssh() {
  local target
  local cmd=(ssh)

  target="$(deploy::ssh_target)"

  if [[ -n "${SSH_CONFIG_FILE:-}" ]]; then
    cmd+=(-F "${SSH_CONFIG_FILE}")
  fi

  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    cmd+=(-i "${SSH_KEY_PATH}")
  fi

  cmd+=("${target}")
  "${cmd[@]}" "$@"
}

deploy::rsync_rsh() {
  local parts=()

  if [[ -n "${RSYNC_RSH:-}" ]]; then
    printf '%s\n' "${RSYNC_RSH}"
    return 0
  fi

  parts=(ssh)

  if [[ -n "${SSH_CONFIG_FILE:-}" ]]; then
    parts+=(-F "${SSH_CONFIG_FILE}")
  fi

  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    parts+=(-i "${SSH_KEY_PATH}")
  fi

  printf '%q ' "${parts[@]}"
  printf '\n'
}

deploy::quote_args() {
  printf '%q ' "$@"
}

deploy::run_remote_shell() {
  local shell_code="$1"
  deploy::run_ssh "bash -lc $(printf '%q' "${shell_code}")"
}

deploy::ensure_remote_dir() {
  local remote_dir="$1"
  deploy::run_remote_shell "mkdir -p $(printf '%q' "${remote_dir}")"
}

deploy::remote_path() {
  local requested_path="$1"

  if [[ "${requested_path}" = /* ]] || [[ "${requested_path}" == ~* ]]; then
    printf '%s\n' "${requested_path}"
  else
    printf '%s/%s\n' "${HPC_BASEDIR%/}" "${requested_path}"
  fi
}

deploy::resolve_local_path() {
  local requested_path="$1"

  if [[ -e "${requested_path}" ]]; then
    printf '%s\n' "${requested_path}"
    return 0
  fi

  if [[ -e "${DEPLOY_REPO_ROOT}/${requested_path}" ]]; then
    printf '%s\n' "${DEPLOY_REPO_ROOT}/${requested_path}"
    return 0
  fi

  return 1
}

deploy::join_by_comma() {
  local old_ifs="${IFS}"
  IFS=,
  printf '%s' "$*"
  IFS="${old_ifs}"
}

deploy::rsync_to_remote() {
  local source_path="$1"
  local remote_dest="$2"
  shift 2

  rsync -a --human-readable --itemize-changes \
    -e "$(deploy::rsync_rsh)" \
    "$@" \
    "${source_path}" \
    "$(deploy::ssh_target):${remote_dest}"
}
