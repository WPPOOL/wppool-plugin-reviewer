#!/bin/bash
# WPPOOL Plugin Reviewer - Install Script
# Installs skill to Claude Code skills directory

set -e

SKILL_NAME="wppool-plugin-reviewer"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect OS
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    ACCOUNT_SKILLS="$USERPROFILE/.claude-account2/skills"
    PROJECT_SKILLS=".claude/skills"
else
    ACCOUNT_SKILLS="$HOME/.claude-account2/skills"
    PROJECT_SKILLS=".claude/skills"
fi

echo "=== WPPOOL Plugin Reviewer Installer ==="
echo ""
echo "Where to install?"
echo "  1) Account-level (available in ALL projects) [recommended]"
echo "  2) Current project only"
echo ""
read -p "Choice [1/2]: " choice

case "$choice" in
    2)
        TARGET="$PROJECT_SKILLS/$SKILL_NAME"
        echo "Installing to project: $TARGET"
        ;;
    *)
        TARGET="$ACCOUNT_SKILLS/$SKILL_NAME"
        echo "Installing to account: $TARGET"
        ;;
esac

# Create target directory
mkdir -p "$TARGET/knowledge"

# Copy files
cp "$SCRIPT_DIR/SKILL.md" "$TARGET/SKILL.md"
cp "$SCRIPT_DIR/knowledge/"*.md "$TARGET/knowledge/"

# Don't copy install scripts or README to skill dir if installing from repo
if [ "$SCRIPT_DIR" != "$TARGET" ]; then
    echo ""
    echo "Installed files:"
    find "$TARGET" -type f | sort | while read f; do
        echo "  $f"
    done
fi

echo ""
echo "Done! Restart Claude Code and type /wppool-plugin-reviewer to verify."
