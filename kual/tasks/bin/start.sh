#!/bin/sh
# Tasks: показ дашборда на весь екран з оновленням кожні INTERVAL с.
# Поки дашборд на екрані, інтерфейс Kindle (lab126_gui) зупинено, щоб він не малював поверх.
# Вихід: дотик до екрана або кнопка живлення → stop.sh знову запускає інтерфейс.

. /mnt/us/extensions/tasks/bin/common.sh

# KUAL не чекає на довгі дії — від'єднуємося у фон
if [ "$1" != "run" ]; then
	log "start: викликано з KUAL"
	# окрема сесія, щоб зупинка lab126_gui (а з ним і KUAL) не вбила цикл
	if command -v setsid >/dev/null 2>&1; then
		setsid /bin/sh "$0" run >/dev/null 2>&1 </dev/null &
	else
		nohup /bin/sh "$0" run >/dev/null 2>&1 </dev/null &
	fi
	exit 0
fi

if [ -f $RUN/loop.pid ] && kill -0 "$(cat $RUN/loop.pid)" 2>/dev/null; then
	log "start: вже працює"
	exit 0
fi
mkdir -p $RUN
echo $$ >$RUN/loop.pid

if [ -z "$KEY" ]; then
	log "start: нема KEY у $CONF"
	note "Tasks: no KEY in tasks.conf"
	rm -f $RUN/loop.pid
	exit 1
fi

# зберегти стан, щоб stop.sh його відновив
lipc-get-prop com.lab126.cmd wirelessEnable >$RUN/wifi_was 2>/dev/null
# preventScreenSaver блокує й кнопку живлення, тому лише скидаємо таймер сну (keepalive)
lipc-set-prop com.lab126.cmd wirelessEnable 1
log "start: pid $$, wifi_was=$(cat $RUN/wifi_was)"

# слухач кнопки живлення: одна подія → коректний вихід
(
	lipc-wait-event com.lab126.powerd goingToScreenSaver >/dev/null 2>&1
	log "powerd: goingToScreenSaver"
	/bin/sh $EXT/bin/stop.sh
) &
echo $! >$RUN/listener.pid

find_touch() {
	name=""
	while read -r l; do
		case "$l" in
		"N: Name="*) name=$(echo "$l" | tr 'A-Z' 'a-z') ;;
		"H: Handlers="*)
			case "$name" in
			*touch*|*zforce*|*cyttsp*|*_ts*|*elan*) echo "$l" | grep -o 'event[0-9]*'; return ;;
			esac ;;
		esac
	done </proc/bus/input/devices
}

# без setsid цикл живе в одній групі процесів з KUAL і загинув би разом з інтерфейсом
if [ "$KIOSK" = "1" ] && ! command -v setsid >/dev/null 2>&1; then
	log "kiosk: нема setsid — інтерфейс не зупиняю"
	KIOSK=0
fi

if [ "$KIOSK" = "1" ]; then
	log "input: $(grep '^N: Name' /proc/bus/input/devices | tr '\n' ';')"
	stop lab126_gui >>$LOG 2>&1
	rc=$?
	log "stop lab126_gui rc=$rc"
	[ $rc -eq 0 ] && touch $RUN/gui_stopped

	# дотик до екрана → вихід (інтерфейс зупинено, тож дотики більше нікуди не йдуть)
	TOUCH=$(find_touch)
	if [ -n "$TOUCH" ]; then
		(
			sleep 5  # пропустити залишки тапу по KUAL
			dd if=/dev/input/$TOUCH of=/dev/null bs=16 count=1 2>/dev/null
			log "touch: вихід"
			/bin/sh $EXT/bin/stop.sh
		) &
		echo $! >$RUN/touch.pid
		log "touch exit на /dev/input/$TOUCH"
	else
		log "touch: сенсор не знайдено, вихід лише кнопкою живлення"
	fi
fi

wait_wifi() {
	i=0
	while [ $i -lt 30 ]; do
		[ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" = "CONNECTED" ] && return 0
		sleep 1; i=$((i+1))
	done
	return 1
}

fetch() {
	# 0 = у $RUN/new.png свіжа валідна картинка
	wait_wifi || { log "fetch: нема Wi-Fi"; return 1; }
	curl -fsS --max-time 40 -o $RUN/tasks.bin "$URL?t=$(date +%s)" 2>>$LOG
	rc=$?
	if [ $rc -eq 60 ] || [ $rc -eq 35 ]; then
		# застарілі CA на Kindle — файл однаково зашифрований
		log "fetch: TLS rc=$rc, повтор з -k"
		curl -fsS -k --max-time 40 -o $RUN/tasks.bin "$URL?t=$(date +%s)" 2>>$LOG
		rc=$?
	fi
	[ $rc -eq 0 ] || { log "fetch: curl rc=$rc"; return 1; }
	iv=$(head -c 16 $RUN/tasks.bin | od -An -tx1 | tr -d ' \n')
	tail -c +17 $RUN/tasks.bin | OPENSSL_CONF=/dev/null openssl enc -d -aes-256-cbc -K "$KEY" -iv "$iv" -out $RUN/new.png 2>>$LOG \
		|| { log "fetch: розшифрування не вдалось; tmp: $(df -k $RUN | tail -1)"; return 1; }
	[ "$(head -c 4 $RUN/new.png | od -An -tx1 | tr -d ' \n')" = "89504e47" ] \
		|| { log "fetch: не PNG"; return 1; }
	return 0
}

# дати KUAL закритися, щоб домашній екран не перемалював нас
sleep 3
eips -c >/dev/null 2>&1
note "Tasks: loading..."

# перевірка keepalive: залишок до сну до і після скидання
log "powerd до: $(lipc-get-prop com.lab126.powerd status | grep Remaining)"
lipc-set-prop com.lab126.powerd touchScreenSaverTimeout 1 2>>$LOG
log "powerd після: $(lipc-get-prop com.lab126.powerd status | grep Remaining)"

n=0
last=""
while true; do
	if fetch; then
		sum=$(md5sum $RUN/new.png | cut -d' ' -f1)
		if [ "$sum" != "$last" ]; then
			n=$((n+1))
			if [ $((n % FULL_EVERY)) -eq 1 ] || [ $FULL_EVERY -le 1 ]; then
				eips -f -g $RUN/new.png >/dev/null 2>&1
			else
				eips -g $RUN/new.png >/dev/null 2>&1
			fi
			mv $RUN/new.png $RUN/shown.png
			last=$sum
			log "draw #$n"
		fi
	else
		# лишаємо останню картинку, внизу — позначка про збій
		note "Tasks: update failed $(date +%H:%M)"
	fi
	# чекаємо INTERVAL, скидаючи таймер автосну щохвилини
	t=0
	while [ $t -lt $INTERVAL ]; do
		lipc-set-prop com.lab126.powerd touchScreenSaverTimeout 1 2>/dev/null
		sleep 60 &
		echo $! >$RUN/sleep.pid
		wait $!
		t=$((t+60))
	done
done
