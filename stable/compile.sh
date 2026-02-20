#!/bin/bash

# desc: compile and run c/c++ file
# notes: c17 / c++20
# deps: clang mold

ARGS=(
    -Wall -Wextra -Werror
    -O2 -pipe -fuse-ld=mold
    -o executable
)

info() { echo "[INFO] $*"; }
die() {
    local ret=$1
    shift
    echo "[ERROR] $*"
    exit "$ret"
}

isolated_run() {
    local tmp
    tmp="$(mktemp -d)" || die $? Failed to create temp directory
    "$@" -o "$tmp/exe" || die $? Failed to compile

    info Compile success
    "$tmp/exe" || die $? Failed to execute program

    printf '\n'
    rm -rf "$tmp"
}

run_c() {
    isolated_run clang -std=c17 "${ARGS[@]}" "$@"
}

run_cpp() {
    isolated_run clang++ -std=c++20 "${ARGS[@]}" "$@"
}
