#!/bin/bash
# +-------------------------------------------------------------------
# | Custom aaPanel Installer with Sub-Account (Multiple Users) Unlocked
# +-------------------------------------------------------------------
# | This script installs aaPanel then applies custom patches from
# | the cloned repository to enable the Sub-Account feature for free.
# +-------------------------------------------------------------------

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

set -e

PANEL_PATH="/www/server/panel"
REPO_PATH="$(cd "$(dirname "$0")" && pwd)"
BACKUP_PATH="/root/aaPanel_backup_$(date +%Y%m%d_%H%M%S)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Root check
if [ $(whoami) != "root" ]; then
    err "Please run as root"
fi

# OS check
is64bit=$(getconf LONG_BIT)
if [ "${is64bit}" != '64' ]; then
    err "aaPanel does not support 32-bit systems"
fi

log "=========================================="
log "Custom aaPanel Installer"
log "Sub-Account (Multiple Users) Unlocked"
log "Repo path: ${REPO_PATH}"
log "=========================================="

# ─── Step 1: Install aaPanel ────────────────────────────────────────
if [ ! -f "${PANEL_PATH}/BT-Panel" ]; then
    if [ -f "${REPO_PATH}/install.sh" ]; then
        log "Step 1: Installing aaPanel using repo's bundled installer..."
        log "This may take 5-10 minutes depending on your server."
        bash "${REPO_PATH}/install.sh" 66959f96
    else
        log "Step 1: Installing aaPanel via official online installer..."
        log "This may take 5-10 minutes depending on your server."
        INSTALL_URL="https://www.aapanel.com/script/install_6.0_en.sh"
        INSTALL_SCRIPT="install_aapanel_official.sh"
        if command -v curl &>/dev/null; then
            curl -ksS -o "${INSTALL_SCRIPT}" "${INSTALL_URL}"
        else
            wget --no-check-certificate -O "${INSTALL_SCRIPT}" "${INSTALL_URL}"
        fi
        if [ ! -f "${INSTALL_SCRIPT}" ]; then
            err "Failed to download the official aaPanel installer"
        fi
        bash "${INSTALL_SCRIPT}" 66959f96
        rm -f "${INSTALL_SCRIPT}"
    fi
    if [ ! -f "${PANEL_PATH}/BT-Panel" ]; then
        err "aaPanel installation failed - BT-Panel not found at ${PANEL_PATH}"
    fi
    log "aaPanel installed successfully."
else
    warn "aaPanel appears to already be installed at ${PANEL_PATH}"
    warn "Skipping official installer. Patching only."
fi

# ─── Step 2: Stop panel services ──────────────────────────────────────
log "Step 2: Stopping panel services..."
if [ -f "/etc/init.d/bt" ]; then
    /etc/init.d/bt stop 2>/dev/null || true
fi
# Also kill any lingering processes
pkill -f "BT-Panel" 2>/dev/null || true
pkill -f "BT-Task" 2>/dev/null || true
sleep 2

# ─── Step 3: Backup original files ────────────────────────────────────
log "Step 3: Backing up original panel files to ${BACKUP_PATH}..."
mkdir -p "${BACKUP_PATH}"
cp -r "${PANEL_PATH}/class"         "${BACKUP_PATH}/class"        2>/dev/null || true
cp -r "${PANEL_PATH}/class_v2"      "${BACKUP_PATH}/class_v2"     2>/dev/null || true
cp -r "${PANEL_PATH}/BTPanel"       "${BACKUP_PATH}/BTPanel"      2>/dev/null || true
cp    "${PANEL_PATH}/data/config.json" "${BACKUP_PATH}/config.json" 2>/dev/null || true
log "Backup complete."

# ─── Step 4: Apply custom patches ─────────────────────────────────────
log "Step 4: Applying custom patches from repository..."

# 4a: Copy modified Python modules
log "  -> Copying class/ modules..."
cp -r "${REPO_PATH}/class/"*       "${PANEL_PATH}/class/"       2>/dev/null || true
cp -r "${REPO_PATH}/class_v2/"*    "${PANEL_PATH}/class_v2/"    2>/dev/null || true

# 4b: Copy modified frontend JS
log "  -> Copying frontend JS..."
cp -r "${REPO_PATH}/BTPanel/"*     "${PANEL_PATH}/BTPanel/"     2>/dev/null || true

# 4c: Create sentinel files for Pro status
log "  -> Creating Pro sentinel files..."
touch "${PANEL_PATH}/data/.is_pro.pl"
touch "${PANEL_PATH}/data/panel_pro.pl"

# 4d: Verify key patches were applied
log "Step 4d: Verifying patches..."

VERIFY_FAIL=0

if grep -q 'return {"status": True, "msg": "pro"}' "${PANEL_PATH}/class_v2/config_v2.py" 2>/dev/null; then
    log "  [OK] config_v2.py is_pro patched"
else
    warn "  [MISSING] config_v2.py patch not found"
    VERIFY_FAIL=1
fi

if [ -f "${PANEL_PATH}/data/.is_pro.pl" ]; then
    log "  [OK] .is_pro.pl sentinel file exists"
else
    warn "  [MISSING] .is_pro.pl not found"
    VERIFY_FAIL=1
fi

if grep -q 'table.total>=99999' "${PANEL_PATH}/BTPanel/static/vite/js/accountState-CCqf6Ges.js" 2>/dev/null; then
    log "  [OK] Account limit removed (99999)"
else
    warn "  [MISSING] Account limit patch not found"
    VERIFY_FAIL=1
fi

if grep -q 'userInfo.status||false' "${PANEL_PATH}/BTPanel/static/vite/js/index-Cr9LAN38.js" 2>/dev/null; then
    log "  [OK] Router pro guard removed"
else
    warn "  [MISSING] Router pro guard patch not found"
    VERIFY_FAIL=1
fi

# ─── Step 5: Fix permissions ──────────────────────────────────────────
log "Step 5: Setting permissions..."
chmod -R 700 "${PANEL_PATH}/pyenv/bin" 2>/dev/null || true
chmod 700 "${PANEL_PATH}/BT-Panel"     2>/dev/null || true
chmod 700 "${PANEL_PATH}/BT-Task"      2>/dev/null || true

# ─── Step 6: Restart panel ────────────────────────────────────────────
log "Step 6: Restarting panel..."
if [ -f "/etc/init.d/bt" ]; then
    /etc/init.d/bt start
    sleep 3
    /etc/init.d/bt status
fi

# ─── Step 7: Display credentials ──────────────────────────────────────
log "=========================================="
if [ "${VERIFY_FAIL}" -eq 0 ]; then
    log "Installation complete!"
    log "All patches verified successfully."
else
    warn "Installation complete with some warnings."
    warn "Some patches could not be verified. Check the messages above."
fi
log "=========================================="
log "Your custom aaPanel is ready with Sub-Account feature unlocked!"
log ""
log "Access panel at: http://YOUR_SERVER_IP:$(cat ${PANEL_PATH}/data/port.pl 2>/dev/null || echo '8888')"
log ""
log "Original installation credentials were shown during install."
log "If you forgot them, run: /etc/init.d/bt default"
log ""
log "Backup saved to: ${BACKUP_PATH}"
log "=========================================="
