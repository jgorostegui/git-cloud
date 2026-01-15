# git-cloud

Manage git repos in cloud-synced folders (Google Drive, Dropbox, OneDrive) without corruption.

## The Problem

When you store git repos in cloud-synced folders:
- Multiple machines modify `.git/` simultaneously
- Cloud sync causes corruption (dangling blobs, index conflicts, lock files)
- `git fsck` shows errors, repos break randomly

## The Solution

Keep your **working files** in the cloud, but store `.git/` **locally** on each machine:

```
~/GoogleDrive/dev/my-project/     ← Synced by cloud
├── src/                          ← Code (synced)
├── .env                          ← Secrets (synced, gitignored)
├── .git-remote                   ← Remote URL (synced, gitignored)
└── .git                          ← Pointer file (synced)
        ↓
        "gitdir: ~/.git-dirs/GoogleDrive/dev/my-project"
        ↓
~/.git-dirs/GoogleDrive/dev/my-project/   ← LOCAL (not synced)
├── objects/
├── refs/
└── ...
```

## Installation

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/jgorostegui/git-cloud/main/install.sh | bash

# Or manual
git clone https://github.com/jgorostegui/git-cloud.git
cd git-cloud
./install.sh
```

## Setup (once per machine)

### 1. Configure your cloud sync client

**Insync** (Google Drive):
```
Account Settings → Ignore Rules → Add:
.git/
```

**Dropbox**:
```bash
echo ".git/" >> ~/Dropbox/rules.dropboxignore
```

> **Important**: Only ignore `.git/` (directory), NOT `.git` (file). The pointer file should sync!

### 2. Configure git to ignore `.git-remote`

```bash
echo ".git-remote" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

## Usage

### Clone a new repo into cloud folder

```bash
git-cloud clone git@github.com:user/repo.git ~/GoogleDrive/dev/repo
```

This:
- Clones to `~/GoogleDrive/dev/repo/`
- Stores `.git` in `~/.git-dirs/GoogleDrive/dev/repo/`
- Creates `.git-remote` with the URL (for other machines)

### Setup on another machine (after cloud sync)

Files arrive via cloud sync, but no `.git` yet:

```bash
cd ~/GoogleDrive/dev/repo
git-cloud setup
```

This reads the URL from `.git-remote` and sets up git locally.

### Migrate existing repo

If you already have a repo with `.git/` in your cloud folder:

```bash
cd ~/GoogleDrive/dev/existing-repo
git-cloud migrate
```

This moves `.git/` to local storage and creates a pointer.

### Check status of all repos

```bash
git-cloud status
```

Shows:
- ✓ Properly configured repos
- ! Repos with `.git/` directory (need migration)
- ✗ Broken pointers (need setup)
- ? Folders with `.git-remote` but no `.git`

## Workflow Example

```
┌─────────────────────────────────────────────────────────────────┐
│ LAPTOP (first time)                                             │
│                                                                 │
│ $ git-cloud clone git@github.com:me/project ~/GDrive/project   │
│                                                                 │
│ Cloud syncs: src/, .env, .git-remote                           │
│ Local only: ~/.git-dirs/GDrive/project/                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (cloud sync)
┌─────────────────────────────────────────────────────────────────┐
│ DESKTOP (after sync)                                            │
│                                                                 │
│ $ cd ~/GDrive/project                                          │
│ ⚠ Run 'git-cloud setup' to enable git                          │
│                                                                 │
│ $ git-cloud setup                                              │
│ Reading URL from .git-remote...                                │
│ Done!                                                          │
│                                                                 │
│ $ git status                                                   │
│ On branch main                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `git-cloud clone <url> [path]` | Clone with local `.git` storage |
| `git-cloud setup [url] [path]` | Setup git for synced folder |
| `git-cloud migrate [path]` | Move existing `.git` to local storage |
| `git-cloud status` | Show all repos and their state |
| `git-cloud help` | Show help |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GIT_DIRS` | `~/.git-dirs` | Where to store `.git` directories |
| `CLOUD_DIRS` | `~/GoogleDrive:~/Dropbox:~/OneDrive` | Cloud folders to scan (colon-separated) |

## How it Works

Git supports storing the `.git` directory separately from the working tree using:
- `git clone --separate-git-dir=<path>` for new clones
- A `.git` **file** (not directory) containing `gitdir: /path/to/.git`

This is a standard git feature, not a hack. The `git-cloud` tool just automates the workflow.

## Troubleshooting

### "fatal: not a git repository"
Run `git-cloud setup` to connect the repo.

### Cloud sync is syncing `.git/` anyway
Make sure you're ignoring `.git/` (with trailing slash) in your cloud client.
The `.git` file (pointer) SHOULD sync - only the directory should be ignored.

### Repos showing as modified after setup
This is normal if files differ from remote. Run `git status` to see what changed.

## License

MIT
