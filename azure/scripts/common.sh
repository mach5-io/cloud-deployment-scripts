#!/usr/bin/env bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE_DEFAULT="$SCRIPT_DIR/../configs/mach5.env"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_FILE_DEFAULT}"
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}

log() {
  printf "[%s] %s\n" "$1" "$2"
}

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    printf "Config file %s not found\n" "$CONFIG_FILE" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

execute() {
  local cmd=("$@")
  if [[ "$VERBOSE" == true ]]; then
    printf "+ %q" "${cmd[0]}"
    for fragment in "${cmd[@]:1}"; do
      printf " %q" "$fragment"
    done
    printf "\n"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi
  "${cmd[@]}"
}

handle_error() {
  local exit_code=$1
  local line_no=$2
  local cmd="$3"
  printf "ERROR: command '%s' failed at line %s (exit %s)\n" "$cmd" "$line_no" "$exit_code" >&2
}

trap 'handle_error $? ${LINENO} "$BASH_COMMAND"' ERR
