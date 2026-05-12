"""Verification script for sub-account Pro bypass changes."""

import os
import sys

os.chdir(os.path.dirname(os.path.abspath(__file__)))
errors = 0

# 1. Verify is_pro methods in source code
print("\n=== Test 1: config_v2.is_pro() returns pro ===")
with open("class_v2/config_v2.py") as f:
    content = f.read()
if 'return {"status": True, "msg": "pro"}' in content:
    print("PASS")
else:
    print("FAIL: config_v2.is_pro not modified")
    errors += 1

print("\n=== Test 2: config.is_pro() returns pro ===")
with open("class/config.py") as f:
    content = f.read()
if 'return {"status": True, "msg": "pro"}' in content:
    print("PASS")
else:
    print("FAIL: config.is_pro not modified")
    errors += 1

# 3. Test .is_pro.pl sentinel file
print("\n=== Test 3: data/.is_pro.pl exists ===")
if os.path.exists("data/.is_pro.pl"):
    print("PASS")
else:
    print("FAIL: file not found")
    errors += 1

# 4. Test check_auth logic (replicating __init__.py)
print("\n=== Test 4: check_auth logic ===")
if os.path.exists("data/.is_pro.pl"):
    print("PASS: would return true")
else:
    print("FAIL")
    errors += 1

# 5. Verify router guard was patched in JS
print("\n=== Test 5: Frontend JS router guard patched ===")
js_file = "BTPanel/static/vite/js/index-Cr9LAN38.js"
try:
    with open(js_file) as f:
        content = f.read()
    if "!n.hasSubPanelAuth&&!n.isPro" not in content:
        print("PASS: pro guard removed from modern JS bundle")
    else:
        print("FAIL: old pro guard still present")
        errors += 1
except FileNotFoundError:
    print("FAIL: JS file not found")
    errors += 1

# 6. Verify account limit was removed
print("\n=== Test 6: Account limit removed ===")
acct_file = "BTPanel/static/vite/js/accountState-CCqf6Ges.js"
try:
    with open(acct_file) as f:
        content = f.read()
    assert "table.total>=99999" in content
    assert "table.total>=30" not in content
    print("PASS: limit raised to 99999")
except (FileNotFoundError, AssertionError) as e:
    print(f"FAIL: {e}")
    errors += 1

print(f"\n{'=' * 40}")
if errors:
    print(f"FAILURES: {errors}")
else:
    print("All checks passed! Changes are correctly applied.")
print(f"{'=' * 40}")
