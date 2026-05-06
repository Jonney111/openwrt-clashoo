#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UPDATE_ALL="$ROOT_DIR/clashoo/files/usr/share/clashoo/update/update_all.sh"

if grep -q 'cat /tmp/geoip_update.txt >> "$UPDATE_LOG"' "$UPDATE_ALL"; then
	echo "update_all.sh still copies GeoIP detail log into the main update log" >&2
	exit 1
fi

grep -q 'sh /usr/share/clashoo/update/geoip.sh' "$UPDATE_ALL" || {
	echo "update_all.sh no longer runs the GeoIP update task" >&2
	exit 1
}
