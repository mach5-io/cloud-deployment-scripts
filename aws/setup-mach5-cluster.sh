#!/bin/bash

set -e

export M5_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
 
MODE="$1"

if [[ "$MODE" == "single" ]]; then
    "$M5_BASE_DIR/scripts/onenode.sh" 
else
    "$M5_BASE_DIR/scripts/multinode.sh" 
fi
