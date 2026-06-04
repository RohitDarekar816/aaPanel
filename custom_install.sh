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

# 4a: Copy modified Python modules (skip encrypted model files to preserve installed version)
log "  -> Copying class/ modules..."
cp -r "${REPO_PATH}/class/"*       "${PANEL_PATH}/class/"       2>/dev/null || true
find "${REPO_PATH}/class_v2/" -maxdepth 1 -type f \( -name '*.py' -o -name '*.so' \) -not -path '*/panelModelV2/publicModel.py' -exec cp -r {} "${PANEL_PATH}/class_v2/" \; 2>/dev/null || true
# Also copy subdirectories but skip encrypted publicModel.py
for dir in "${REPO_PATH}/class_v2/"*/; do
    dirname=$(basename "$dir")
    if [ "$dirname" = "panelModelV2" ]; then
        mkdir -p "${PANEL_PATH}/class_v2/panelModelV2"
        find "$dir" -maxdepth 1 -type f -not -name 'publicModel.py' -exec cp {} "${PANEL_PATH}/class_v2/panelModelV2/" \; 2>/dev/null || true
    else
        cp -r "$dir" "${PANEL_PATH}/class_v2/" 2>/dev/null || true
    fi
done

# 4b: Patch frontend JS files dynamically (handles all hash variants)
log "  -> Patching frontend JS files..."

# Patch account limit (table.total>=30 -> 99999) in ALL accountState JS bundles
find "${PANEL_PATH}/BTPanel/static/vite/js" -name 'accountState*.js' -exec sed -i 's/table\.total>=30/table.total>=99999/g' {} \;

# Patch router pro guard in ALL index JS bundles
# Pattern: !<var>.userInfo.status||!<var>.hasSubPanelAuth&&!<var>.isPro
find "${PANEL_PATH}/BTPanel/static/vite/js" -name 'index*.js' -exec sed -r -i 's/!([a-z]+)\.userInfo\.status\|\|!\1\.hasSubPanelAuth&&!\1\.isPro/!\1.userInfo.status||false/g' {} \;

# Patch /binds redirect guard (newer aaPanel versions)
# Pattern: !<var>.userInfo.status&&<var>.aaPanelPro?...redirect /binds
# For modern builds: !n.userInfo.status&&n.aaPanelPro?e.path==="/binds"?s():s("/binds")
# For legacy builds: !o.userInfo.status&&o.aaPanelPro?"/binds"===e.path?i():i("/binds")
find "${PANEL_PATH}/BTPanel/static/vite/js" -name 'index*.js' -exec sed -r -i 's/![a-z]+\.userInfo\.status&&[a-z]+\.aaPanelPro\?/false?/g' {} \;

# 4c: Create sentinel files for Pro status
log "  -> Creating Pro sentinel files..."
touch "${PANEL_PATH}/data/.is_pro.pl"
touch "${PANEL_PATH}/data/panel_pro.pl"

# 4c-extra: Force Lifetime (pro=0) in get_pd() to hide "Expire on" date
# NOTE: class/public/common.py is already patched via repo copy in 4a
# app.py is NOT copied from repo, so we patch it via sed
log "  -> Forcing Lifetime pro status in get_pd()..."
sed -i 's/            if tmp: tmp = int(tmp)/            if tmp: tmp = int(tmp)\n            tmp = 0  # Force Lifetime (patched)/' "${PANEL_PATH}/BTPanel/app.py"

# 4d: Force disable trial/unlock pro in backend response
log "  -> Forcing trail=0 and pro=0 in plugin API responses..."
sed -i 's/        return softList/        softList['"'"'trail'"'"'] = 0\n        softList['"'"'pro'"'"'] = 0  # Force Lifetime Pro (patched)\n        return softList/' "${PANEL_PATH}/class/panelPlugin.py" 2>/dev/null || true
sed -i 's/        return softList/        softList['"'"'trail'"'"'] = 0\n        softList['"'"'pro'"'"'] = 0  # Force Lifetime Pro (patched)\n        return softList/' "${PANEL_PATH}/class_v2/panel_plugin_v2.py" 2>/dev/null || true

# 4e: Verify key patches were applied
log "Step 4e: Verifying patches..."

VERIFY_FAIL=0

if grep -q 'get_secret_key' "${PANEL_PATH}/class/public/common.py" 2>/dev/null; then
    log "  [OK] public/common.py get_secret_key() present"
else
    warn "  [MISSING] public/common.py get_secret_key() not found"
    VERIFY_FAIL=1
fi

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

if grep -q 'pro = 0  # Force Lifetime' "${PANEL_PATH}/class/public/common.py" 2>/dev/null; then
    log "  [OK] common.py get_pd pro=0 (Lifetime) patched"
else
    warn "  [MISSING] common.py Lifetime patch not found"
    VERIFY_FAIL=1
fi

if grep -q 'tmp = 0  # Force Lifetime' "${PANEL_PATH}/BTPanel/app.py" 2>/dev/null; then
    log "  [OK] app.py get_pd pro=0 (Lifetime) patched"
else
    warn "  [MISSING] app.py Lifetime patch not found"
    VERIFY_FAIL=1
fi

if grep -q "softList\['trail'\] = 0" "${PANEL_PATH}/class/panelPlugin.py" 2>/dev/null; then
    log "  [OK] panelPlugin.py trail=0 patched"
else
    warn "  [MISSING] panelPlugin.py trail=0 patch not found"
    VERIFY_FAIL=1
fi

if grep -q "softList\['pro'\] = 0  # Force Lifetime Pro" "${PANEL_PATH}/class/panelPlugin.py" 2>/dev/null; then
    log "  [OK] panelPlugin.py pro=0 (Lifetime Pro) patched"
else
    warn "  [MISSING] panelPlugin.py pro=0 (Lifetime Pro) patch not found"
    VERIFY_FAIL=1
fi

if grep -q "softList\['trail'\] = 0" "${PANEL_PATH}/class_v2/panel_plugin_v2.py" 2>/dev/null; then
    log "  [OK] panel_plugin_v2.py trail=0 patched"
else
    warn "  [MISSING] panel_plugin_v2.py trail=0 patch not found"
    VERIFY_FAIL=1
fi

if grep -q "softList\['pro'\] = 0  # Force Lifetime Pro" "${PANEL_PATH}/class_v2/panel_plugin_v2.py" 2>/dev/null; then
    log "  [OK] panel_plugin_v2.py pro=0 (Lifetime Pro) patched"
else
    warn "  [MISSING] panel_plugin_v2.py pro=0 (Lifetime Pro) patch not found"
    VERIFY_FAIL=1
fi

ACCT_COUNT=$(grep -l 'table.total>=30' "${PANEL_PATH}/BTPanel/static/vite/js/accountState"*.js 2>/dev/null | wc -l)
if [ "${ACCT_COUNT}" -eq 0 ]; then
    ACCT_PATCHED=$(grep -l 'table.total>=99999' "${PANEL_PATH}/BTPanel/static/vite/js/accountState"*.js 2>/dev/null | wc -l)
    log "  [OK] Account limit removed (99999) in ${ACCT_PATCHED} files"
else
    warn "  [MISSING] ${ACCT_COUNT} accountState file(s) still have limit=30"
    VERIFY_FAIL=1
fi

GUARD_COUNT=$(grep -l 'hasSubPanelAuth&&.*isPro' "${PANEL_PATH}/BTPanel/static/vite/js/index"*.js 2>/dev/null | wc -l)
if [ "${GUARD_COUNT}" -eq 0 ]; then
    GUARD_PATCHED=$(grep -l 'userInfo.status||false' "${PANEL_PATH}/BTPanel/static/vite/js/index"*.js 2>/dev/null | wc -l)
    log "  [OK] Router pro guard removed in ${GUARD_PATCHED} files"
else
    warn "  [MISSING] ${GUARD_COUNT} index file(s) still have the pro guard"
    VERIFY_FAIL=1
fi

BINDS_COUNT=$(grep -c '[a-z]\.aaPanelPro?' "${PANEL_PATH}/BTPanel/static/vite/js/index"*.js 2>/dev/null | grep -v ':0$' | wc -l)
if [ "${BINDS_COUNT}" -eq 0 ]; then
    log "  [OK] /binds redirect guard patched in all index files"
else
    warn "  [MISSING] ${BINDS_COUNT} index file(s) still have the /binds guard"
    VERIFY_FAIL=1
fi

# ─── Step 5: Fix permissions ──────────────────────────────────────────
log "Step 5: Setting permissions..."
chmod -R 700 "${PANEL_PATH}/pyenv/bin" 2>/dev/null || true
chmod 700 "${PANEL_PATH}/BT-Panel"     2>/dev/null || true
chmod 700 "${PANEL_PATH}/BT-Task"      2>/dev/null || true

# ─── Step 6: Clear Python cache ────────────────────────────────────────
log "Step 6: Clearing Python bytecode cache..."
find "${PANEL_PATH}/class"     -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${PANEL_PATH}/BTPanel"   -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${PANEL_PATH}/class_v2"  -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
log "Python cache cleared."

# ─── Step 7: Restart panel ────────────────────────────────────────────
log "Step 7: Restarting panel..."
if [ -f "/etc/init.d/bt" ]; then
    /etc/init.d/bt start
    sleep 3
    /etc/init.d/bt status
fi

# ─── Step 8: Display credentials ──────────────────────────────────────
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
