#!/bin/sh
# Копіює KUAL-розширення Tasks на змонтований Kindle.
set -e
K=/Volumes/Kindle
[ -d "$K/extensions" ] || { echo "Kindle не змонтований ($K/extensions нема)"; exit 1; }
rsync -rt --delete --exclude ".DS_Store" "$(dirname "$0")/kual/tasks/" "$K/extensions/tasks/"
# прибрати AppleDouble-сміття (._*), яке macOS лишає на FAT
find "$K/extensions/tasks" -name "._*" -delete
sync
ls -R "$K/extensions/tasks"
