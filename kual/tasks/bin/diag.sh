#!/bin/sh
# Tasks: діагностика середовища Kindle. Пише все в /mnt/us/tasks_diag.log.
# Нічого не змінює, окрім тимчасового ввімкнення Wi-Fi (стан відновлюється в кінці).

LOG=/mnt/us/tasks_diag.log

# KUAL не чекає на довгі дії — від'єднуємося у фон.
if [ "$1" != "run" ]; then
	/bin/sh "$0" run >/dev/null 2>&1 &
	exit 0
fi

msg() { eips 1 30 "$1                                        " >/dev/null 2>&1; }
sec() { echo; echo "===== $* ====="; }
run() { echo "\$ $*"; "$@" 2>&1; echo "[rc=$?]"; }

HTTPS_URLS="https://pages.github.com/ https://github.io/ https://raw.githubusercontent.com/github/gitignore/main/README.md https://example.com/ https://workers.cloudflare.com/"
HTTP_URLS="http://example.com/ http://neverssl.com/"

msg "Tasks diag: running..."

{
sec "basic"
date; date -u
run uptime
cat /etc/prettyversion.txt 2>/dev/null
cat /etc/version.txt 2>/dev/null
run uname -a
run id

sec "space / mounts"
run df -h
mount | grep -E " /mnt/us | /var/local | /tmp | / "
run free

sec "tools"
for t in curl wget openssl eips fbink lipc-get-prop lipc-set-prop lipc-wait-event lipc-send-event lipc-probe python python3 busybox timeout nslookup ping ip ifconfig sha1sum md5sum base64 awk sed; do
	p=$(command -v $t 2>/dev/null)
	echo "$t: ${p:-MISSING}"
done
run curl --version
run openssl version -a
busybox 2>&1 | head -2
echo "-- wget help (head):"
wget --help 2>&1 | head -5
echo "-- CA files:"
ls -la /etc/ssl/certs 2>&1 | head -5
ls -la /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem /etc/pki/tls/certs/ca-bundle.crt 2>&1

sec "eips"
run eips -i

sec "extensions on /mnt/us"
ls /mnt/us/extensions

sec "powerd"
run lipc-get-prop com.lab126.powerd status
run lipc-get-prop com.lab126.powerd state
lipc-probe -v com.lab126.powerd 2>&1 | head -60

sec "wifi before"
WIFI_WAS=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)
echo "wirelessEnable=$WIFI_WAS"
run lipc-get-prop com.lab126.wifid cmState
run lipc-get-prop com.lab126.wifid signalStrength

sec "wifi enable + wait"
lipc-set-prop com.lab126.cmd wirelessEnable 1
i=0; ST=""
while [ $i -lt 45 ]; do
	ST=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
	[ "$ST" = "CONNECTED" ] && break
	sleep 1; i=$((i+1))
done
echo "cmState=$ST after ${i}s"
ifconfig wlan0 2>&1 | head -3
cat /etc/resolv.conf 2>&1
sleep 2

msg "Tasks diag: network tests..."

sec "DNS"
for h in pages.github.com raw.githubusercontent.com example.com; do
	echo "-- $h"; nslookup $h 2>&1 | tail -3
done

sec "curl HTTPS"
for u in $HTTPS_URLS; do
	echo "-- $u"
	curl -sS -o /dev/null -L --max-time 25 -w "code=%{http_code} size=%{size_download} sslverify=%{ssl_verify_result} t=%{time_total}\n" "$u" 2>&1
	echo "   with -k:"
	curl -sS -k -o /dev/null -L --max-time 25 -w "   code=%{http_code} size=%{size_download} t=%{time_total}\n" "$u" 2>&1
done

sec "curl HTTP"
for u in $HTTP_URLS; do
	echo "-- $u"
	curl -sS -o /dev/null --max-time 25 -w "code=%{http_code} size=%{size_download} t=%{time_total}\n" "$u" 2>&1
done

sec "curl -v pages.github.com (TLS details)"
curl -v -o /dev/null --max-time 25 https://pages.github.com/ 2>&1 | grep -iE "CAfile|CApath|SSL connection|TLS|subject:|issuer:|expire|error|HTTP/" | head -30

sec "openssl s_client"
for h in pages.github.com raw.githubusercontent.com; do
	echo "-- $h"
	echo | openssl s_client -connect $h:443 -servername $h 2>&1 | grep -E "Protocol|Cipher|Verify return|verify error|depth=" | head -10
done

sec "wget"
echo "-- wget https"
wget -q -O /dev/null -T 25 https://pages.github.com/ 2>&1; echo "[rc=$?]"
echo "-- wget http"
wget -q -O /dev/null -T 25 http://example.com/ 2>&1; echo "[rc=$?]"

sec "wifi restore"
if [ "$WIFI_WAS" = "0" ]; then
	lipc-set-prop com.lab126.cmd wirelessEnable 0
	echo "wifi turned back off"
else
	echo "wifi left on (was $WIFI_WAS)"
fi

sec "done"
date
} >"$LOG" 2>&1

sync
msg "Tasks diag: DONE -> tasks_diag.log"
