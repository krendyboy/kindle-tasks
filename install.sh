#!/bin/sh
# Копіює KUAL-розширення Tasks на змонтований Kindle і кладе туди tasks.conf з ключем.
set -e
cd "$(dirname "$0")"
K=/Volumes/Kindle
[ -d "$K/extensions" ] || { echo "Kindle не змонтований ($K/extensions нема)"; exit 1; }
[ -f secrets/tasks_key ] || { echo "нема secrets/tasks_key"; exit 1; }
printf 'KEY=%s\n' "$(cat secrets/tasks_key)" > kual/tasks/tasks.conf
rsync -rt --delete --exclude ".DS_Store" kual/tasks/ "$K/extensions/tasks/"
# прибрати AppleDouble-сміття (._*), яке macOS лишає на FAT
find "$K/extensions/tasks" -name "._*" -delete
sync
ls -R "$K/extensions/tasks"
