#!/bin/sh
# Tasks: перевірка виводу PNG через eips -g (кирилиця, 16 відтінків сірого).
# Лог: /mnt/us/tasks_testimg.log

LOG=/mnt/us/tasks_testimg.log
IMG=/mnt/us/extensions/tasks/test.png

if [ "$1" != "run" ]; then
	/bin/sh "$0" run >/dev/null 2>&1 &
	exit 0
fi

{
	date
	ls -la "$IMG"
	# даємо KUAL закритися, щоб домашній екран не перемалював картинку
	sleep 3
	echo "\$ eips -c"; eips -c; echo "[rc=$?]"
	echo "\$ eips -f -g $IMG"; eips -f -g "$IMG"; echo "[rc=$?]"
} >"$LOG" 2>&1
sync
