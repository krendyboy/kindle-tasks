#!/bin/sh
# Tasks: зупинити цикл і відновити стан Kindle. Можна викликати скільки завгодно разів.

. /mnt/us/extensions/tasks/bin/common.sh

[ -d $RUN ] || exit 0

# не даємо двом виходам (дотик + кнопка) спрацювати одночасно
mkdir $RUN/stopping 2>/dev/null || exit 0

for p in loop listener touch sleep; do
	[ -f $RUN/$p.pid ] && kill "$(cat $RUN/$p.pid)" 2>/dev/null
done
# прибрати осиротілих слухачів
pkill -f "lipc-wait-event com.lab126.powerd goingToScreenSaver" 2>/dev/null
pkill -f "dd if=/dev/input/" 2>/dev/null

lipc-set-prop com.lab126.powerd preventScreenSaver 0
[ "$(cat $RUN/wifi_was 2>/dev/null)" = "0" ] && lipc-set-prop com.lab126.cmd wirelessEnable 0

if [ -f $RUN/gui_stopped ]; then
	note "Tasks: starting Kindle UI..."
	start lab126_gui >>$LOG 2>&1
	log "start lab126_gui rc=$?"
fi

log "stop: wifi_was=$(cat $RUN/wifi_was 2>/dev/null)"
rm -rf $RUN
