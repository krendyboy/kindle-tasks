# Спільне для start.sh / stop.sh. Підключається через ". common.sh".

EXT=/mnt/us/extensions/tasks
CONF=$EXT/tasks.conf
RUN=/tmp/tasks
LOG=/mnt/us/tasks.log

# значення за замовчуванням; tasks.conf їх перекриває
URL=https://krendyboy.github.io/kindle-tasks/tasks.bin
KEY=
INTERVAL=300     # як часто перевіряти, с
FULL_EVERY=4     # повний рефреш (з миганням) кожне N-те оновлення картинки
KIOSK=1          # 1 = на час показу зупиняти інтерфейс Kindle (lab126_gui)
[ -f "$CONF" ] && . "$CONF"

log() {
	# лог не більше ~100 КБ
	[ -f "$LOG" ] && [ "$(wc -c <"$LOG")" -gt 100000 ] && tail -c 50000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
	echo "$(date '+%m-%d %H:%M:%S') $*" >>"$LOG"
}

# текст ASCII поверх картинки в нижньому рядку (eips не вміє кирилицю)
note() { eips 1 39 "$1                                        " >/dev/null 2>&1; }
