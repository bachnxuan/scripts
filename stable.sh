#!/bin/bash
# shellcheck disable=SC1090

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd -P)"

shopt -s nullglob
source "$SCRIPT_DIR/script"/*.sh
