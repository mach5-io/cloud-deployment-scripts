#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG_PREFIX="$(basename "$0")"

check_helm_major() {
  if ! command -v helm >/dev/null 2>&1; then
    printf "ERROR: Helm 3 is required but 'helm' was not found in PATH.\n" >&2
    exit 1
  fi

  local version=""
  version=$(helm version --short 2>/dev/null || true)
  if [[ -z "$version" ]]; then
    version=$(helm version --template '{{.Version}}' 2>/dev/null || true)
  fi

  local major=""
  major=$(printf '%s' "$version" | sed -n 's/^v\([0-9]\+\).*/\1/p' | head -n 1)
  if [[ "$major" != "3" ]]; then
    printf "ERROR: Helm 3 is required; detected %s.\n" "${version:-unknown}" >&2
    exit 1
  fi
}

check_helm_major

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

./scripts/mach5-infrastructure.sh "${ALL_ARGS[@]}"
deploy_exit=$?
if [[ "$deploy_exit" -eq 10 ]]; then
  log_prefix "License token missing; stopping before Helm installs."
  exit 0
elif [[ "$deploy_exit" -ne 0 ]]; then
  log_prefix "Infrastructure deployment failed; stopping."
  exit "$deploy_exit"
fi

log_prefix "Infrastructure deployment completed; moving to Helm installs."

./scripts/mach5-helm.sh "${ALL_ARGS[@]}"
printf "\n"
printf "========================= SETUP COMPLETE =========================\n"
printf "Mach5 infrastructure and Helm installs finished successfully.\n"
printf "==================================================================\n\n"
