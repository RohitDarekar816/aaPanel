# aaPanel — Agent Guide

## Architecture

- **Two processes**: `BT-Panel` (Flask/gevent WSGI server) and `BT-Task` (background task daemon), both at repo root.
- **Two API generations**: `class/` (v1 routes in `BTPanel/__init__.py`) and `class_v2/` (v2 routes in `BTPanel/routes/v2.py`). v2 is prefixed with `/v2`. Both active.
- **Panel base path**: hardcoded `/www/server/panel` everywhere. The repo source expects to run from there (`os.chdir` on import).
- **Dual module pattern**: v1 = `class/module.py`, v2 = `class_v2/module_v2.py`. When modifying behavior, check if both versions exist and patch both.
- **Plugin system**: plugins live in `plugin/`; loader is `class/PluginLoader.*.so` (arch/glibc-specific).

## Key Commands

| Action | Command |
|--------|---------|
| Restart panel | `/etc/init.d/bt restart` |
| Start/stop/reload | `/etc/init.d/bt start\|stop\|reload` |
| CLI tool menu | `bt` (interactive, 22 options inc. password/port/cache) |
| Debug mode | `touch data/debug.pl` + restart (auto-reloads on file changes via pyinotify) |
| Dev server | `python runserver.py` (reads port from `data/port.pl`) |
| Prod config | `runconfig.py` — gunicorn with gevent WebSocket worker |
| Test (pro bypass) | `python test_subaccount.py [path]` — standalone verification script |
| Python | `/www/server/panel/pyenv/bin/python3` (virtual env) |

## State Files (in `data/`)

The panel uses sentinel `.pl` files for configuration:
- `port.pl` — panel port (default 8888)
- `debug.pl` — enables debug/auto-reload mode
- `ssl.pl` — enables HTTPS
- `admin_path.pl` — security entrance path
- `.is_pro.pl` — marks panel as Pro (no license check)
- `domain.conf` — domain bind whitelist
- `limitip.conf` — IP access whitelist

## Important Quirks

- **`hook_import()`** runs at module load in `BTPanel/__init__.py` — can intercept arbitrary imports. May cause unexpected import behavior.
- **CSRF check** is enforced via `x-http-token` header on all POST requests (except when debug mode is on).
- **Pro gating** is patched in multiple places: `config_v2.py`, `config.py`, `BTPanel/app.py`, `class/public/common.py`, and JS bundles in `BTPanel/static/vite/js/`.
- **SSL**: when enabled, panel uses `ssl/certificate.pem` and `ssl/privateKey.pem` with TLS 1.2+ only.
- **i18n**: translations loaded via `public.translations.load_translations()`; login page has separate loader.
- **No standard test framework** — only `test_subaccount.py` exists for validating pro-bypass patches.
- **Debug mode** watches filesystem with pyinotify and auto-reloads panel or task on `.py/.html/.so` changes.

## Code Style

- `#coding: utf-8` header on all Python files
- Chinese comments throughout
- Panel path references are absolute (`/www/server/panel`) — never assume CWD
