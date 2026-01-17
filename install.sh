#!/bin/bash
# git-cloud installer
# https://github.com/jgorostegui/git-cloud

set -e

red()    { echo -e "\033[0;31m$1\033[0m"; }
green()  { echo -e "\033[0;32m$1\033[0m"; }
yellow() { echo -e "\033[1;33m$1\033[0m"; }
blue()   { echo -e "\033[0;34m$1\033[0m"; }

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ask() {
    local prompt="$1"
    local default="${2:-n}"
    local yn
    if [ "$default" = "y" ]; then
        read -r -p "$prompt [Y/n] " yn
        yn="${yn:-y}"
    else
        read -r -p "$prompt [y/N] " yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy]$ ]]
}

detect_shell_rc() {
    if [ -n "$ZSH_VERSION" ] || [[ "$SHELL" == *zsh* ]]; then
        echo "$HOME/.zshrc"
    else
        echo "$HOME/.bashrc"
    fi
}

echo ""
blue "╔═══════════════════════════════════════╗"
blue "║       git-cloud installer             ║"
blue "╚═══════════════════════════════════════╝"
echo ""

# 1. Install script (always)
echo "Installing git-cloud to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

if [ -f "$SCRIPT_DIR/git-cloud" ]; then
    cp "$SCRIPT_DIR/git-cloud" "$INSTALL_DIR/git-cloud"
else
    echo "Downloading from GitHub..."
    curl -fsSL https://raw.githubusercontent.com/jgorostegui/git-cloud/main/git-cloud \
        -o "$INSTALL_DIR/git-cloud"
fi

chmod +x "$INSTALL_DIR/git-cloud"
green "✓ Installed to $INSTALL_DIR/git-cloud"

# Create .git-dirs (always)
mkdir -p "$HOME/.git-dirs"
green "✓ Created ~/.git-dirs"

echo ""
blue "── Optional configuration ──"
echo ""

SHELL_RC=$(detect_shell_rc)

# 2. PATH (only if needed)
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    if ask "Add $INSTALL_DIR to PATH in $SHELL_RC?"; then
        {
            echo ''
            echo '# git-cloud: PATH'
            # shellcheck disable=SC2016
            echo 'export PATH="$HOME/.local/bin:$PATH"'
        } >> "$SHELL_RC"
        green "✓ Added PATH to $SHELL_RC"
    else
        yellow "⚠ Skipped. Add manually: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
else
    green "✓ PATH already configured"
fi

# 3. Completion
if ! grep -q '_git_cloud()' "$SHELL_RC" 2>/dev/null; then
    echo ""
    if ask "Add bash/zsh completion for git-cloud?"; then
        cat >> "$SHELL_RC" << 'EOF'

# git-cloud: completion
_git_cloud() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "clone setup migrate status version help" -- "$cur"))
    fi
}
complete -F _git_cloud git-cloud
EOF
        green "✓ Added completion to $SHELL_RC"
    fi
fi

# 4. cd hook
if ! grep -q 'git-cloud: cd hook' "$SHELL_RC" 2>/dev/null; then
    echo ""
    echo "The cd hook shows a warning when you enter a synced folder without .git:"
    echo "  $ cd ~/GoogleDrive/dev/my-repo"
    yellow "  ⚠ Run 'git-cloud setup' to enable git here"
    echo ""
    if ask "Add cd hook?"; then
        cat >> "$SHELL_RC" << 'EOF'

# git-cloud: cd hook
cd() {
    builtin cd "$@" || return
    if [[ -f .git-remote && ! -e .git ]]; then
        echo -e "\033[1;33m⚠ Run 'git-cloud setup' to enable git here\033[0m"
    fi
}
EOF
        green "✓ Added cd hook to $SHELL_RC"
    fi
fi

# 5. Global gitignore
echo ""
if ask "Configure global .gitignore to ignore .git-remote files?"; then
    GITIGNORE_GLOBAL="$HOME/.gitignore_global"

    if [ ! -f "$GITIGNORE_GLOBAL" ]; then
        touch "$GITIGNORE_GLOBAL"
    fi

    if ! grep -q '.git-remote' "$GITIGNORE_GLOBAL" 2>/dev/null; then
        echo ".git-remote" >> "$GITIGNORE_GLOBAL"
    fi

    git config --global core.excludesfile "$GITIGNORE_GLOBAL"
    green "✓ Added .git-remote to $GITIGNORE_GLOBAL"
fi

# Done
echo ""
blue "═══════════════════════════════════════"
green "Installation complete!"
echo ""
echo "Next steps:"
echo ""
echo "  1. Reload shell: source $SHELL_RC"
echo ""
echo "  2. Add .git/ to cloud sync ignore rules:"
echo "     Insync:  Account Settings → Ignore Rules → .git/"
echo "     Dropbox: echo '.git/' >> ~/Dropbox/rules.dropboxignore"
echo ""
echo "  3. Usage:"
echo "     git-cloud clone <url> ~/GoogleDrive/dev/repo"
echo "     git-cloud help"
echo ""
