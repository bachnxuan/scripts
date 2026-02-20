#!/bin/bash

WORKDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# shellcheck disable=SC1090
source "$WORKDIR/stable"/*