"""Verification script for sub-account Pro bypass changes.

Usage:
    python test_subaccount.py              # test repo source
    python test_subaccount.py /www/server/panel  # test live installation
"""

import os
import sys
import glob

target = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
os.chdir(target)
print(f"Testing target: {target}")

errors = 0

# 1. Verify is_pro methods in source code
print("\n=== Test 1: config_v2.is_pro() returns pro ===")
try:
    with open("class_v2/config_v2.py") as f:
        content = f.read()
    if 'return {"status": True, "msg": "pro"}' in content:
        print("PASS")
    else:
        print("FAIL: config_v2.is_pro not modified")
        errors += 1
except FileNotFoundError:
    print("SKIP (not found)")

print("\n=== Test 2: config.is_pro() returns pro ===")
try:
    with open("class/config.py") as f:
        content = f.read()
    if 'return {"status": True, "msg": "pro"}' in content:
        print("PASS")
    else:
        print("FAIL: config.is_pro not modified")
        errors += 1
except FileNotFoundError:
    print("SKIP (not found)")

# 3. Test .is_pro.pl sentinel file
print("\n=== Test 3: data/.is_pro.pl exists ===")
if os.path.exists("data/.is_pro.pl"):
    print("PASS")
elif not os.path.exists("data"):
    print("SKIP (data dir not found)")
else:
    print("FAIL: file not found")
    errors += 1

# 4. Test check_auth logic (replicating __init__.py)
print("\n=== Test 4: check_auth logic ===")
if os.path.exists("data/.is_pro.pl"):
    print("PASS: would return true")
elif not os.path.exists("data"):
    print("SKIP (data dir not found)")
else:
    print("FAIL")
    errors += 1

# 5. Verify router guard was patched in ALL index JS bundles
print("\n=== Test 5: Frontend JS router guard patched ===")
idx_dir = "BTPanel/static/vite/js"
if not os.path.isdir(idx_dir):
    print("SKIP (JS dir not found)")
else:
    idx_files = glob.glob(f"{idx_dir}/index*.js")
    had_guard = [f for f in idx_files if "hasSubPanelAuth" in open(f, errors="ignore").read()]
    still_bad = [f for f in had_guard if "hasSubPanelAuth&&" in open(f).read() and "isPro" in open(f).read()]
    patched = [f for f in had_guard if "userInfo.status||false" in open(f).read()]
    if still_bad:
        print(f"FAIL: {len(still_bad)} file(s) still have the old pro guard:")
        for f in still_bad:
            print(f"  - {f}")
        errors += 1
    elif not had_guard:
        print("FAIL: no index files contain hasSubPanelAuth at all")
        errors += 1
    elif not patched:
        print("FAIL: no patched guard found despite finding files with hasSubPanelAuth")
        errors += 1
    else:
        missed = [f for f in had_guard if "userInfo.status||false" not in open(f).read()]
        if missed:
            print(f"INFO: {len(missed)} file(s) have hasSubPanelAuth in destructure only (no guard to patch):")
            for f in missed:
                print(f"  - {os.path.basename(f)}")
        print(f"PASS: {len(patched)} file(s) with patched guard")

# 6. Verify account limit was removed in ALL accountState JS bundles
print("\n=== Test 6: Account limit removed ===")
if not os.path.isdir(idx_dir):
    print("SKIP (JS dir not found)")
else:
    acct_files = glob.glob(f"{idx_dir}/accountState*.js")
    still_30 = [f for f in acct_files if "table.total>=30" in open(f).read()]
    patched_99999 = [f for f in acct_files if "table.total>=99999" in open(f).read()]
    if still_30:
        print(f"FAIL: {len(still_30)} file(s) still have limit=30:")
        for f in still_30:
            print(f"  - {f}")
        errors += 1
    elif not acct_files:
        print("FAIL: no accountState files found")
        errors += 1
    elif not patched_99999:
        print(f"FAIL: none of {len(acct_files)} accountState files have the patched limit")
        errors += 1
    else:
        print(f"PASS: {len(patched_99999)}/{len(acct_files)} accountState files patched to 99999")

# 7. Verify pro=0 Lifetime patch in get_pd()
print("\n=== Test 7: get_pd() returns pro=0 (Lifetime) ===")
patches_found = 0
try:
    with open("class/public/common.py") as f:
        if "pro = 0  # Force Lifetime" in f.read():
            print("PASS: common.py get_pd forces pro=0")
            patches_found += 1
except FileNotFoundError:
    print("SKIP (common.py not found)")

try:
    with open("BTPanel/app.py") as f:
        if "tmp = 0  # Force Lifetime" in f.read():
            print("PASS: app.py get_pd forces tmp=0")
            patches_found += 1
except FileNotFoundError:
    print("SKIP (app.py not found)")

if patches_found == 0:
    print("FAIL: no Lifetime patch found in either file")
    errors += 1

print(f"\n{'=' * 40}")
if errors:
    print(f"FAILURES: {errors}")
    sys.exit(1)
else:
    print("All checks passed! Changes are correctly applied.")
print(f"{'=' * 40}")
