# kindle-tasks

Дашборд задач з Notion («Kindle Tasks») на jailbroken Kindle Paperwhite 2.

- `render.py` — Notion API → PNG 758×1024 (16 відтінків сірого, PT Sans) → `tasks.bin` (AES-256-CBC: 16 байт IV + шифротекст).
- `.github/workflows/render.yml` — кожні 15 хв рендерить і публікує на GitHub Pages лише зашифрований `tasks.bin`.
- `kual/tasks/` — KUAL-розширення для Kindle (копіюється `install.sh`).

Секрети репозиторію: `NOTION_TOKEN`, `TASKS_KEY` (64 hex). Той самий ключ лежить на Kindle у `extensions/tasks/tasks.conf` (не в git).

Локально: `python3 render.py --fixture sample.json`.
Шрифт PT Sans — ParaType, SIL OFL 1.1 (`fonts/OFL.txt`).
