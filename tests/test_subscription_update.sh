#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ONE="$ROOT/clashoo/files/usr/share/clashoo/update/subscription_update.sh"
CRON="$ROOT/clashoo/files/usr/share/clashoo/update/subscription_update_cron.sh"
INIT="$ROOT/clashoo/files/etc/init.d/clashoo"
RPC="$ROOT/luci-app-clashoo/root/usr/share/rpcd/ucode/luci.clashoo"
UI="$ROOT/luci-app-clashoo/htdocs/luci-static/resources/view/clashoo/config.js"
OVERVIEW="$ROOT/luci-app-clashoo/htdocs/luci-static/resources/view/clashoo/overview.js"
CFG="$ROOT/clashoo/files/etc/config/clashoo"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_file_contains() {
	grep -F "$2" "$1" >/dev/null 2>&1 || fail "$1 missing: $2"
}

assert_file_not_contains() {
	! grep -F "$2" "$1" >/dev/null 2>&1 || fail "$1 unexpectedly contains: $2"
}

[ -f "$ONE" ] || fail "shared subscription updater is missing"
[ -f "$CRON" ] || fail "subscription cron runner is missing"

assert_file_contains "$CFG" "option auto_subscription_update '0'"
assert_file_contains "$CFG" "option subscription_update_interval '72'"
assert_file_contains "$INIT" "/usr/share/clashoo/update/subscription_update_cron.sh"
assert_file_contains "$RPC" "subscription_update_all:"
assert_file_contains "$RPC" "subscription_update_status:"
assert_file_contains "$RPC" "set_subscription_update_schedule:"
assert_file_contains "$RPC" "SUBSCRIPTION_UPDATE_SCRIPT = '/usr/share/clashoo/update/subscription_update.sh'"
assert_file_contains "$RPC" "' --mihomo '"
assert_file_contains "$RPC" "' --singbox '"
assert_file_contains "$UI" "定时更新订阅"
assert_file_contains "$UI" "立即更新全部"
assert_file_not_contains "$RPC" "c.set('clashoo', 'config', 'config_update_name', name)"
assert_file_contains "$RPC" "update_current_subscription:"
assert_file_contains "$RPC" "reason: 'not_subscription'"
assert_file_contains "$OVERVIEW" "method: 'update_current_subscription'"
assert_file_not_contains "$OVERVIEW" "var callDownloadSubs = rpc.declare"
assert_file_contains "$OVERVIEW" "当前配置为自定义文件，无需更新订阅"
assert_file_contains "$OVERVIEW" "'info'"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/bin" "$TMP/sub" "$TMP/singbox" "$TMP/custom" "$TMP/backup" "$TMP/etc"
cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
case "$*" in
	*"get clashoo.config.use_config"*) printf '%s\n' "${TEST_USE_CONFIG:-}" ;;
	*"get clashoo.config.config_type"*) printf '%s\n' "${TEST_CONFIG_TYPE:-1}" ;;
	*"get clashoo.config.singbox_active"*) printf '%s\n' "${TEST_SB_ACTIVE:-}" ;;
	*"get clashoo.config.sub_ua"*) printf '%s\n' "clash.meta" ;;
	*"get clashoo.config.auto_subscription_update"*) printf '%s\n' "${TEST_AUTO_UPDATE:-1}" ;;
	*"get clashoo.config.subscription_update_interval"*) printf '%s\n' "72" ;;
	*"get luci.main.lang"*) printf '%s\n' "zh_cn" ;;
	*) exit 1 ;;
esac
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
out=""
hdr=""
url=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		-o) out="$2"; shift 2 ;;
		-D) hdr="$2"; shift 2 ;;
		-w) shift 2 ;;
		http*) url="$1"; shift ;;
		*) shift ;;
	esac
done
case "$url" in *fail*) exit 22 ;; esac
cp "$TEST_DOWNLOAD_FILE" "$out"
[ -n "$hdr" ] && : >"$hdr"
printf '200'
EOF
cat >"$TMP/bin/service" <<'EOF'
#!/bin/sh
case "$1" in
	status) exit "${TEST_SERVICE_STATUS:-0}" ;;
	restart) echo restart >>"$TEST_RESTART_LOG" ;;
esac
EOF
chmod +x "$TMP/bin/uci" "$TMP/bin/curl" "$TMP/bin/service"

printf 'alpha#https://example.test/sub#meta\n' >"$TMP/backup/confit_list.conf"
printf 'proxies:\n  - name: old\n' >"$TMP/sub/alpha"
cp "$TMP/sub/alpha" "$TMP/download.yaml"

run_update() {
	PATH="$TMP/bin:$PATH" \
	CLASHOO_SUB_DIR="$TMP/sub" \
	CLASHOO_SINGBOX_DIR="$TMP/singbox" \
	CLASHOO_BACKUP_DIR="$TMP/backup" \
	CLASHOO_TEMPLATE_DIR="$TMP/custom" \
	CLASHOO_STATUS_FILE="$TMP/backup/status" \
	CLASHOO_LOCK_DIR="$TMP/lock" \
	CLASHOO_SERVICE_CMD="$TMP/bin/service" \
	TEST_DOWNLOAD_FILE="$TMP/download.yaml" \
	TEST_RESTART_LOG="$TMP/restarts" \
	TEST_USE_CONFIG="$TMP/sub/alpha" \
	TEST_CONFIG_TYPE=1 \
	sh "$ONE" "$@"
}

before="$(cksum "$TMP/sub/alpha")"
rm -f "$TMP/backup/status"
run_update --mihomo alpha
after="$(cksum "$TMP/sub/alpha")"
[ "$before" = "$after" ] || fail "unchanged subscription was overwritten"
[ ! -e "$TMP/sub/alpha-2" ] || fail "duplicate subscription file was generated"
[ ! -e "$TMP/backup/status" ] || fail "single update overwrote batch status"
[ ! -e "$TMP/restarts" ] || fail "unchanged active config restarted service"

printf 'proxies:\n  - name: new\n' >"$TMP/download.yaml"
run_update --mihomo alpha
assert_file_contains "$TMP/sub/alpha" "name: new"
[ ! -e "$TMP/backup/status" ] || fail "single update changed cron last-run state"
[ "$(wc -l <"$TMP/restarts" | tr -d ' ')" = "1" ] || fail "changed active config did not restart once"

printf 'beta#https://fail.example.test/sub#meta\n' >>"$TMP/backup/confit_list.conf"
printf 'proxies:\n  - name: beta-old\n' >"$TMP/sub/beta"
printf 'proxies:\n  - name: batch-new\n' >"$TMP/download.yaml"
: >"$TMP/restarts"
run_update --all || true
assert_file_contains "$TMP/sub/alpha" "name: batch-new"
assert_file_contains "$TMP/sub/beta" "name: beta-old"
assert_file_contains "$TMP/backup/status" "failed=1"
[ "$(wc -l <"$TMP/restarts" | tr -d ' ')" = "1" ] || fail "batch update restarted more than once"

printf '{"outbounds":[{"type":"direct","tag":"direct"}]}\n' >"$TMP/singbox/native.json"
printf 'https://example.test/native\n' >"$TMP/singbox/native.json.url"
printf '{"outbounds":[{"type":"direct","tag":"updated"}]}\n' >"$TMP/download.yaml"
TEST_SB_ACTIVE=native.json run_update --singbox native.json
assert_file_contains "$TMP/singbox/native.json" '"tag":"updated"'

cat >"$TMP/bin/update-all" <<'EOF'
#!/bin/sh
echo run >>"$TEST_CRON_LOG"
EOF
chmod +x "$TMP/bin/update-all"
now="$(date +%s)"
printf 'last_run=%s\n' "$now" >"$TMP/backup/cron-status"
PATH="$TMP/bin:$PATH" CLASHOO_STATUS_FILE="$TMP/backup/cron-status" \
	CLASHOO_SUBSCRIPTION_UPDATER="$TMP/bin/update-all" CLASHOO_SERVICE_CMD="$TMP/bin/service" \
	TEST_CRON_LOG="$TMP/cron-runs" TEST_RESTART_LOG="$TMP/restarts" \
	sh "$CRON"
[ ! -e "$TMP/cron-runs" ] || fail "cron ran before interval elapsed"
printf 'last_run=0\n' >"$TMP/backup/cron-status"
PATH="$TMP/bin:$PATH" CLASHOO_STATUS_FILE="$TMP/backup/cron-status" \
	CLASHOO_SUBSCRIPTION_UPDATER="$TMP/bin/update-all" CLASHOO_SERVICE_CMD="$TMP/bin/service" \
	TEST_CRON_LOG="$TMP/cron-runs" TEST_RESTART_LOG="$TMP/restarts" \
	sh "$CRON"
[ "$(wc -l <"$TMP/cron-runs" | tr -d ' ')" = "1" ] || fail "cron did not run after interval elapsed"
TEST_AUTO_UPDATE=0 PATH="$TMP/bin:$PATH" CLASHOO_STATUS_FILE="$TMP/backup/cron-status" \
	CLASHOO_SUBSCRIPTION_UPDATER="$TMP/bin/update-all" CLASHOO_SERVICE_CMD="$TMP/bin/service" \
	TEST_CRON_LOG="$TMP/cron-runs" TEST_RESTART_LOG="$TMP/restarts" sh "$CRON"
[ "$(wc -l <"$TMP/cron-runs" | tr -d ' ')" = "1" ] || fail "disabled cron still ran"
TEST_SERVICE_STATUS=1 PATH="$TMP/bin:$PATH" CLASHOO_STATUS_FILE="$TMP/backup/cron-status" \
	CLASHOO_SUBSCRIPTION_UPDATER="$TMP/bin/update-all" CLASHOO_SERVICE_CMD="$TMP/bin/service" \
	TEST_CRON_LOG="$TMP/cron-runs" TEST_RESTART_LOG="$TMP/restarts" sh "$CRON"
[ "$(wc -l <"$TMP/cron-runs" | tr -d ' ')" = "1" ] || fail "cron ran while service was stopped"

echo "PASS: subscription update behavior"
