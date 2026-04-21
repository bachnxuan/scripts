#!/usr/bin/env bash
set -euo pipefail

# desc: incremental push (to push large repo to github)
# deps: git

# ============================
# Config (can also be passed via arguments)
# ============================
BRANCH_NAME="${1:-$(git rev-parse --abbrev-ref HEAD)}" # arg1 or current branch
REMOTE_NAME="${2:-origin}"                             # arg2 or origin
STEP_SIZE="${3:-200000}"                               # arg3 or default 200000

# ============================
# Step 1: Collect every n-th commit
# ============================
echo "[INFO] Collecting commit list from branch '$BRANCH_NAME'..."
step_commits=$(git log --oneline --reverse "refs/heads/$BRANCH_NAME" \
    | awk "NR % $STEP_SIZE == 0" | awk '{print $1}')

if [[ -z "$step_commits" ]]; then
    echo "[ERROR] No matching commits found. Try reducing STEP_SIZE."
    exit 1
fi

# ============================
# Step 2: Push commits incrementally
# ============================
echo "[INFO] Starting incremental push to '$REMOTE_NAME/$BRANCH_NAME' with a step size of $STEP_SIZE commits..."
for commit in $step_commits; do
    echo "  → Push commit $commit"
    if ! git push "$REMOTE_NAME" "+$commit:refs/heads/$BRANCH_NAME"; then
        echo "[ERROR] Failed to push commit $commit. Exiting."
        exit 1
    fi
done

# ============================
# Step 3: Final sync
# ============================
echo "[INFO] Final sync for all refs..."
git push "$REMOTE_NAME" --mirror

echo "[OK] Incremental push completed ✅"
