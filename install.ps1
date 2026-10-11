# WPPOOL Plugin Reviewer - Install Script (Windows)
# Installs skill to Claude Code skills directory

$ErrorActionPreference = "Stop"

$SkillName = "wppool-plugin-reviewer"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$AccountSkills = Join-Path $env:USERPROFILE ".claude-account2\skills"
$ProjectSkills = ".claude\skills"

Write-Host "=== WPPOOL Plugin Reviewer Installer ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Where to install?"
Write-Host "  1) Account-level (available in ALL projects) [recommended]"
Write-Host "  2) Current project only"
Write-Host ""

$choice = Read-Host "Choice [1/2]"

switch ($choice) {
    "2" {
        $Target = Join-Path $ProjectSkills $SkillName
        Write-Host "Installing to project: $Target" -ForegroundColor Yellow
    }
    default {
        $Target = Join-Path $AccountSkills $SkillName
        Write-Host "Installing to account: $Target" -ForegroundColor Yellow
    }
}

# Create target directory
New-Item -ItemType Directory -Force -Path (Join-Path $Target "knowledge") | Out-Null

# Copy files
Copy-Item -Force (Join-Path $ScriptDir "SKILL.md") (Join-Path $Target "SKILL.md")
Get-ChildItem (Join-Path $ScriptDir "knowledge\*.md") | ForEach-Object {
    Copy-Item -Force $_.FullName (Join-Path $Target "knowledge\$($_.Name)")
}

# Show installed files
if ($ScriptDir -ne $Target) {
    Write-Host ""
    Write-Host "Installed files:" -ForegroundColor Green
    Get-ChildItem -Recurse -File $Target | ForEach-Object {
        Write-Host "  $($_.FullName)"
    }
}

Write-Host ""
Write-Host "Done! Restart Claude Code and type /wppool-plugin-reviewer to verify." -ForegroundColor Green
