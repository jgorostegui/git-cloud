#!/usr/bin/env bats
# Tests for git-cloud
# Requires: bats-core, git

GIT_CLOUD="$BATS_TEST_DIRNAME/../git-cloud"

setup() {
    # Create isolated temp dirs for each test
    export TEST_DIR="$(mktemp -d)"
    export HOME_ORIG="$HOME"
    export HOME="$TEST_DIR/home"
    export GIT_DIRS="$HOME/.git-dirs"
    export CLOUD_DIRS="$HOME/CloudDrive"

    mkdir -p "$HOME" "$CLOUD_DIRS"

    # Configure git identity (needed since HOME is overridden)
    git config --global user.email "test@test.com"
    git config --global user.name "Test"
    git config --global init.defaultBranch main

    # Create a bare repo to use as "remote"
    export REMOTE_REPO="$TEST_DIR/remote.git"
    git init --bare "$REMOTE_REPO" >/dev/null 2>&1

    # Seed the remote with an initial commit
    local tmp="$TEST_DIR/seed"
    git clone "$REMOTE_REPO" "$tmp" >/dev/null 2>&1
    git -C "$tmp" commit --allow-empty -m "initial" >/dev/null 2>&1
    git -C "$tmp" push >/dev/null 2>&1
    rm -rf "$tmp"

}

teardown() {
    export HOME="$HOME_ORIG"
    rm -rf "$TEST_DIR"
}

# ─── version / help ─────────────────────────────────────────

@test "version prints version string" {
    run bash "$GIT_CLOUD" version
    [ "$status" -eq 0 ]
    [[ "$output" == git-cloud* ]]
}

@test "help prints usage" {
    run bash "$GIT_CLOUD" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMANDS"* ]]
}

@test "no args prints help" {
    run bash "$GIT_CLOUD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMANDS"* ]]
}

@test "unknown command fails" {
    run bash "$GIT_CLOUD" foobar
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# ─── init ────────────────────────────────────────────────────

@test "init creates repo with separate git dir" {
    local project="$CLOUD_DIRS/my-project"
    mkdir -p "$project"

    run bash "$GIT_CLOUD" init "$project"
    [ "$status" -eq 0 ]

    # .git should be a file (pointer), not a directory
    [ -f "$project/.git" ]
    [ ! -d "$project/.git" ]

    # git dir should exist under GIT_DIRS
    local git_dir="$GIT_DIRS/CloudDrive/my-project"
    [ -d "$git_dir" ]

    # git should work from the project
    run git -C "$project" status
    [ "$status" -eq 0 ]
}

@test "init creates directory if it doesn't exist" {
    local project="$CLOUD_DIRS/new-project"

    run bash "$GIT_CLOUD" init "$project"
    [ "$status" -eq 0 ]
    [ -d "$project" ]
    [ -f "$project/.git" ]
}

@test "init defaults to current directory" {
    local project="$CLOUD_DIRS/cwd-project"
    mkdir -p "$project"
    cd "$project"

    run bash "$GIT_CLOUD" init
    [ "$status" -eq 0 ]
    [ -f "$project/.git" ]
}

@test "init fails if already a git repo" {
    local project="$CLOUD_DIRS/existing"
    mkdir -p "$project"
    git init "$project" >/dev/null 2>&1

    run bash "$GIT_CLOUD" init "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Already a git repository"* ]]
}

@test "init fails if git dir already exists" {
    local project="$CLOUD_DIRS/conflict"
    mkdir -p "$project"

    local git_dir="$GIT_DIRS/CloudDrive/conflict"
    mkdir -p "$git_dir"

    run bash "$GIT_CLOUD" init "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Git dir already exists"* ]]
}

# ─── clone ───────────────────────────────────────────────────

@test "clone creates repo with separate git dir" {
    local dest="$CLOUD_DIRS/cloned-repo"

    run bash "$GIT_CLOUD" clone "$REMOTE_REPO" "$dest"
    [ "$status" -eq 0 ]

    # .git is a pointer file
    [ -f "$dest/.git" ]
    [ ! -d "$dest/.git" ]

    # .git-remote was created
    [ -f "$dest/.git-remote" ]
    [[ "$(cat "$dest/.git-remote")" == "$REMOTE_REPO" ]]

    # git dir exists
    local git_dir="$GIT_DIRS/CloudDrive/cloned-repo"
    [ -d "$git_dir" ]

    # git works
    run git -C "$dest" log --oneline
    [ "$status" -eq 0 ]
}

@test "clone fails if destination exists" {
    local dest="$CLOUD_DIRS/exists"
    mkdir -p "$dest"

    run bash "$GIT_CLOUD" clone "$REMOTE_REPO" "$dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Destination already exists"* ]]
}

@test "clone without url shows usage" {
    run bash "$GIT_CLOUD" clone
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

# ─── migrate ─────────────────────────────────────────────────

@test "migrate moves .git to local storage" {
    local project="$CLOUD_DIRS/to-migrate"
    git clone "$REMOTE_REPO" "$project" >/dev/null 2>&1

    # Confirm .git is a directory before migration
    [ -d "$project/.git" ]

    run bash "$GIT_CLOUD" migrate "$project"
    [ "$status" -eq 0 ]

    # .git is now a pointer file
    [ -f "$project/.git" ]
    [ ! -d "$project/.git" ]

    # git dir exists under GIT_DIRS
    local git_dir="$GIT_DIRS/CloudDrive/to-migrate"
    [ -d "$git_dir" ]

    # .git-remote was saved
    [ -f "$project/.git-remote" ]

    # git still works
    run git -C "$project" log --oneline
    [ "$status" -eq 0 ]
}

@test "migrate is idempotent (already migrated)" {
    local project="$CLOUD_DIRS/already-migrated"
    mkdir -p "$project"
    # Simulate already-migrated state
    echo "gitdir: /some/path" > "$project/.git"

    run bash "$GIT_CLOUD" migrate "$project"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already migrated"* ]]
}

@test "migrate fails without .git" {
    local project="$CLOUD_DIRS/no-git"
    mkdir -p "$project"

    run bash "$GIT_CLOUD" migrate "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No .git found"* ]]
}

# ─── setup ───────────────────────────────────────────────────

@test "setup from .git-remote file" {
    local project="$CLOUD_DIRS/to-setup"
    mkdir -p "$project"
    echo "$REMOTE_REPO" > "$project/.git-remote"

    run bash "$GIT_CLOUD" setup "$project"
    [ "$status" -eq 0 ]

    # .git pointer file exists
    [ -f "$project/.git" ]

    # git dir exists
    local git_dir="$GIT_DIRS/CloudDrive/to-setup"
    [ -d "$git_dir" ]

    # git works
    run git -C "$project" log --oneline
    [ "$status" -eq 0 ]
}

@test "setup with explicit url" {
    local project="$CLOUD_DIRS/explicit-url"
    mkdir -p "$project"

    # Pass path first, url second (arg parsing detects directory as path)
    run bash "$GIT_CLOUD" setup "$project" "$REMOTE_REPO"
    [ "$status" -eq 0 ]

    [ -f "$project/.git" ]
    [ -f "$project/.git-remote" ]
}

@test "setup fails without url and no .git-remote" {
    local project="$CLOUD_DIRS/no-url"
    mkdir -p "$project"

    run bash "$GIT_CLOUD" setup "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No URL provided"* ]]
}

@test "setup fails if .git directory exists" {
    local project="$CLOUD_DIRS/has-git-dir"
    git clone "$REMOTE_REPO" "$project" >/dev/null 2>&1
    echo "$REMOTE_REPO" > "$project/.git-remote"

    run bash "$GIT_CLOUD" setup "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *".git directory exists"* ]]
}

@test "setup is idempotent (already set up with valid pointer)" {
    local project="$CLOUD_DIRS/setup-idem"
    mkdir -p "$project"
    echo "$REMOTE_REPO" > "$project/.git-remote"

    # First setup
    bash "$GIT_CLOUD" setup "$project" >/dev/null 2>&1

    # Second setup should succeed (already configured)
    run bash "$GIT_CLOUD" setup "$project"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already set up"* ]]
}

# ─── sync ────────────────────────────────────────────────────

@test "sync fetches and resets to remote" {
    local project="$CLOUD_DIRS/to-sync"

    # Clone via git-cloud
    bash "$GIT_CLOUD" clone "$REMOTE_REPO" "$project" >/dev/null 2>&1

    # Add a commit to remote
    local tmp="$TEST_DIR/push-tmp"
    git clone "$REMOTE_REPO" "$tmp" >/dev/null 2>&1
    echo "new content" > "$tmp/file.txt"
    git -C "$tmp" add file.txt >/dev/null 2>&1
    git -C "$tmp" commit -m "add file" >/dev/null 2>&1
    git -C "$tmp" push >/dev/null 2>&1
    rm -rf "$tmp"

    # Sync should bring the new commit
    run bash "$GIT_CLOUD" sync "$project"
    [ "$status" -eq 0 ]
    [ -f "$project/file.txt" ]
}

@test "sync reports already in sync" {
    local project="$CLOUD_DIRS/in-sync"
    bash "$GIT_CLOUD" clone "$REMOTE_REPO" "$project" >/dev/null 2>&1

    run bash "$GIT_CLOUD" sync "$project"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already in sync"* ]]
}

@test "sync fails if not a git repo" {
    local project="$CLOUD_DIRS/not-a-repo"
    mkdir -p "$project"

    run bash "$GIT_CLOUD" sync "$project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Not a git repository"* ]]
}

# ─── status ──────────────────────────────────────────────────

@test "status shows properly configured repo" {
    local project="$CLOUD_DIRS/status-ok"
    bash "$GIT_CLOUD" clone "$REMOTE_REPO" "$project" >/dev/null 2>&1

    run bash "$GIT_CLOUD" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"status-ok"* ]]
}

@test "status shows repo needing migration" {
    local project="$CLOUD_DIRS/needs-migrate"
    git clone "$REMOTE_REPO" "$project" >/dev/null 2>&1

    run bash "$GIT_CLOUD" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"needs-migrate"* ]]
    [[ "$output" == *"migrate"* ]]
}

@test "status shows no repos when empty" {
    run bash "$GIT_CLOUD" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"No repos found"* ]]
}
