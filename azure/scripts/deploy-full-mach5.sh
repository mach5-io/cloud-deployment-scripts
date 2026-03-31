#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_PREFIX="$(basename "$0")"

usage() {
  cat <<EOF
Usage: $0 [-v|--verbose] [--dry-run] [--config PATH]

Runs the full Mach5 deployment: infrastructure + Helm charts.

Options:
  -v, --verbose    Trace every command in the called scripts.
  --dry-run        Print commands only (implies verbose) in both scripts.
  --config PATH    Use a custom configuration file for every step.
EOF
}

CONFIG_FILE_OVERRIDE=""
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      ARGS+=("$1")
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      ARGS+=("$1")
      shift
      ;;
    --config)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --config" >&2
        usage
        exit 1
      fi
      CONFIG_FILE_OVERRIDE="$2"
      ARGS+=(--config "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

log_prefix() {
  printf "[%s] %s\n" "$LOG_PREFIX" "$1"
}

ALL_ARGS=()
if [[ -n "$CONFIG_FILE_OVERRIDE" ]]; then
  ALL_ARGS+=(--config "$CONFIG_FILE_OVERRIDE")
fi
if [[ "$VERBOSE" == true ]]; then
  ALL_ARGS+=(-v)
fi
if [[ "$DRY_RUN" == true ]]; then
  ALL_ARGS+=(--dry-run)
fi

log_prefix "Starting full Mach5 deployment (infra + Helm)."

./scripts/deploy-mach5.sh "${ALL_ARGS[@]}"
deploy_exit=$?
if [[ "$deploy_exit" -eq 10 ]]; then
  log_prefix "License token missing; stopping before Helm installs."
  exit 0
elif [[ "$deploy_exit" -ne 0 ]]; then
  log_prefix "Infrastructure deployment failed; stopping."
  exit "$deploy_exit"
fi

log_prefix "Infrastructure deployment completed; moving to Helm installs."

./scripts/install-mach5-helm.sh "${ALL_ARGS[@]}"
log_prefix "Helm installs completed."
