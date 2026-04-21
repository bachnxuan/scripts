#!/usr/bin/env bash
set -Eeuo pipefail

info() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

run() {
    info "$*"
    "$@"
}

conflict() {
    local commit="$1"
    local files="$2"

    cat << EOF
Conflict while applying:
$commit

Conflicting files:
$files
EOF
}

setup() {
    REMOTE_NAME="${REMOTE_NAME:-aosp}"
    BASE_BRANCH="${BASE_BRANCH:-android12-5.10-lts}"
    MERGE_BRANCH="${MERGE_BRANCH:-}"
    MERGE_REF=""

    BASE_REF="$REMOTE_NAME/$BASE_BRANCH"
    [[ -n "$MERGE_BRANCH" ]] && MERGE_REF="$REMOTE_NAME/$MERGE_BRANCH"

    REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null)"
    GIT_DIR="$(git rev-parse --git-dir 2> /dev/null)"
    BRANCH_NAME="$(git branch --show-current)"

    STATE_DIR="$GIT_DIR/upstream-${BRANCH_NAME//\//-}"
    COMMITS_FILE="$STATE_DIR/commits.txt"
    NEXT_FILE="$STATE_DIR/next"
    EXPECTED_HEAD_FILE="$STATE_DIR/expected_head"

    cd "$REPO_ROOT"
}

check_clean() {
    if ! git diff --quiet; then
        error "working tree has unstaged changes"
        exit 1
    fi

    if ! git diff --cached --quiet; then
        error "index has staged changes"
        exit 1
    fi

    if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
        error "working tree has untracked files"
        exit 1
    fi
}

record_head() {
    git rev-parse HEAD > "$EXPECTED_HEAD_FILE"
}

validate_head() {
    local expected current

    [[ -f "$EXPECTED_HEAD_FILE" ]] || {
        error "missing state file: $EXPECTED_HEAD_FILE"
        exit 1
    }

    read -r expected < "$EXPECTED_HEAD_FILE"
    current="$(git rev-parse HEAD)"

    if [[ "$current" != "$expected" ]]; then
        error "branch HEAD changed since last run"
        error "expected: $expected"
        error "current:  $current"
        exit 1
    fi
}

init() {
    local ts total backup_branch
    local -a fetch_branches

    check_clean

    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    backup_branch="backup/$BRANCH_NAME-$ts"

    mkdir -p "$STATE_DIR"
    printf '0\n' > "$NEXT_FILE"

    info "current branch: $BRANCH_NAME"
    info "base: $BASE_REF"
    [[ -n "$MERGE_REF" ]] && info "extra merge: $MERGE_REF"
    info "upstream list: $COMMITS_FILE"

    run git branch "$backup_branch" HEAD

    fetch_branches=("$BASE_BRANCH")
    [[ -n "$MERGE_BRANCH" ]] && fetch_branches+=("$MERGE_BRANCH")

    run git fetch "$REMOTE_NAME" "${fetch_branches[@]}"
    run git reset --hard "$BASE_REF"

    [[ -n "$MERGE_REF" ]] && run git merge --no-edit "$MERGE_REF"
    record_head

    git log --reverse --no-merges --format='%H %s' "HEAD..$backup_branch" > "$COMMITS_FILE"

    total="$(wc -l < "$COMMITS_FILE")"
    info "downstream commits count: $total"
}

load() {
    read -r NEXT_INDEX < "$NEXT_FILE"
    mapfile -t COMMITS < "$COMMITS_FILE"
    TOTAL_COMMITS="${#COMMITS[@]}"
}

bump() {
    ((++NEXT_INDEX))
    printf '%s\n' "$NEXT_INDEX" > "$NEXT_FILE"
    record_head
}

skip_empty_pick() {
    [[ -f "$GIT_DIR/CHERRY_PICK_HEAD" ]] || return 1
    git diff HEAD --quiet || return 1

    run git cherry-pick --skip
    bump
    return 0
}

resume() {
    [[ -f "$GIT_DIR/CHERRY_PICK_HEAD" ]] || return 0

    local commit files
    commit="${COMMITS[NEXT_INDEX]}"
    files="$(git diff --name-only --diff-filter=U || true)"

    if [[ -n "$files" ]]; then
        conflict "$commit" "$files"
        exit 1
    fi

    if skip_empty_pick; then
        return 0
    fi

    run git cherry-pick --continue
    bump
}

upstream() {
    local commit sha files

    while ((NEXT_INDEX < TOTAL_COMMITS)); do
        commit="${COMMITS[NEXT_INDEX]}"
        sha="${commit%% *}"

        if run git cherry-pick "$sha"; then
            bump
            continue
        fi

        files="$(git diff --name-only --diff-filter=U || true)"
        if [[ -n "$files" ]]; then
            conflict "$commit" "$files"
            exit 1
        fi

        if skip_empty_pick; then
            continue
        fi

        error "failed to cherry-pick $commit"
        exit 1
    done
}

main() {
    setup
    if [[ -f "$COMMITS_FILE" ]]; then
        info "resuming branch: $BRANCH_NAME"
        info "upstream list: $COMMITS_FILE"
        validate_head
    else
        init
    fi
    load
    resume
    upstream
    rm -rf "$STATE_DIR"
}

trap 'error "Failed at line $LINENO: $BASH_COMMAND"' ERR

main "$@"
