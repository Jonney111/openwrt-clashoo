# clashoo 运行日志格式化
# 输入: /usr/share/clashoo/clashoo.txt 混合格式
# 输出: MM-DD HH:MM:SS msg

# mihomo 原生行
/^time="[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ {
	ts = ""
	if (match($0, /^time="([0-9][0-9][0-9][0-9])-([0-9][0-9])-([0-9][0-9])T([0-9][0-9]:[0-9][0-9]:[0-9][0-9])/, arr)) {
		utc_h = substr(arr[4], 1, 2) + 0
		cst_h = (utc_h + 8) % 24
		ts = sprintf("%s-%s %02d:%s", arr[2], arr[3], cst_h, substr(arr[4], 4))
	}

	prefix = ""
	if (match($0, /level=warning /)) prefix = " [warn]"
	else if (match($0, /level=error /)) prefix = " [err]"
	else if (match($0, /level=fatal /)) prefix = " [fatal]"

	i = index($0, "msg=\"")
	if (i > 0) {
		rest = substr($0, i + 5)
		sub(/"[[:space:]]*$/, "", rest)
		print ts prefix " " rest
		next
	}
	print ts " " $0
	next
}

# log_msg 人工行: 保留月-日 时:分:秒
/^[[:space:]]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]+[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/ {
	ts = substr($0, 1, 30)
	gsub(/^[[:space:]]+/, "", ts)
	sub(/[[:space:]]+$/, "", ts)
	# extract MM-DD HH:MM:SS from "YYYY-MM-DD HH:MM:SS"
	if (match(ts, /[0-9][0-9][0-9][0-9]-([0-9][0-9]-[0-9][0-9]) ([0-9][0-9]:[0-9][0-9]:[0-9][0-9])/, arr)) {
		ts = arr[1] " " arr[2]
	}
	sub(/^[[:space:]]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]+[0-9][0-9]:[0-9][0-9]:[0-9][0-9][[:space:]]*-?[[:space:]]*/, "")
	print ts " " $0
	next
}

# 空行丢弃
NF == 0 { next }

{ print }
