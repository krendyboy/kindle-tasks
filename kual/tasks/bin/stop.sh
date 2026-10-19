#!/bin/sh
# Tasks: зупинити цикл і відновити стан Kindle. Можна викликати скільки завгодно разів.

. /mnt/us/extensions/tasks/bin/common.sh

[ -d $RUN ] || exit 0

for p in loop listener sleep; do
	[ -f $RUN/$p.pid ] && kill "$(cat $RUN/$p.pid)" 2>/dev/null
done
# якщо stop викликано з KUAL — прибрати і самого слухача lipc-wait-event
pkill -f "lipc-wait-event com.lab126.powerd goingToScreenSaver" 2>/dev/null

lipc-set-prop com.lab126.powerd preventScreenSaver 0
[ "$(cat $RUN/wifi_was 2>/dev/null)" = "0" ] && lipc-set-prop com.lab126.cmd wirelessEnable 0

log "stop: wifi_was=$(cat $RUN/wifi_was 2>/dev/null)"
rm -rf $RUN
