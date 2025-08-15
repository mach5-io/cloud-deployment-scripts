#!/bin/bash

set -e

export M5_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
MODE="$1"

if [[ "$MODE" == "eksctl" ]]; then
    "$M5_BASE_DIR/scripts/eksctl.sh" 
else
    "$M5_BASE_DIR/scripts/multinode.sh" 
fi
