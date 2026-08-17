#!/bin/bash
# 讓 AI Meter 拿得到 Claude 額度的「重置時間」。
#
# 為什麼需要動你的檔案：resets_at 只存在於 Claude Code 餵給 statusline 的那份 payload，
# plan-usage-history.json 只有百分比沒有時間。所以我們在 statusline 前面插一層 wrapper，
# 它把 rate_limits 抄到一個檔給 AI Meter 讀，然後把 payload 原封不動交給你原本的 statusline。
#
# 這支腳本會動到 ~/.claude/settings.json，所以：
#   1. 先備份
#   2. 產生 wrapper 後，拿同一份 payload 分別跑「原本的」和「經過 wrapper 的」，diff 比對
#   3. 只有輸出完全一致才改 settings.json；不一致就回滾並報告
#
# 冪等：已經裝好就直接結束，不會疊第二層。
# 反安裝：--uninstall

set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
WRAPPER="$CLAUDE_DIR/statusline-mirror.sh"
MIRROR="$CLAUDE_DIR/rate-limits.json"

die() { echo "✗ $*" >&2; exit 1; }
ok()  { echo "✓ $*"; }

command -v jq >/dev/null || die "需要 jq（brew install jq）"
[ -f "$SETTINGS" ] || die "找不到 ${SETTINGS}——這台機器上還沒設定過 Claude Code？"

current_command() {
  jq -r '.statusLine.command // ""' "$SETTINGS"
}

# ─────────────────────────────────────────────── 反安裝

if [ "${1:-}" = "--uninstall" ]; then
  INNER=$(jq -r '.statusLine.aiMeterWrapped // ""' "$SETTINGS")
  if [ -z "$INNER" ]; then
    echo "沒有偵測到 AI Meter 的 wrapper，不用做什麼"
    exit 0
  fi
  cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  jq --arg c "$INNER" '.statusLine.command = $c | del(.statusLine.aiMeterWrapped)' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv -f "$SETTINGS.tmp" "$SETTINGS"
  rm -f "$WRAPPER" "$MIRROR"
  ok "已還原 statusLine.command 為：$INNER"
  exit 0
fi

# ─────────────────────────────────────────────── 已裝過就結束

ORIGINAL=$(current_command)
if [ "$(jq -r '.statusLine.aiMeterWrapped // ""' "$SETTINGS")" != "" ]; then
  ok "已經裝好了（${WRAPPER}），沒有變更"
  exit 0
fi

# 沒有 aiMeterWrapped 但指令已經指向 wrapper：舊版留下的狀態。
# 再包一層會變成 wrapper 呼叫 wrapper，無限遞迴。
case "$ORIGINAL" in
  *statusline-mirror.sh*)
    die "settings.json 已經指向 ${WRAPPER}，但缺少還原資訊。"$'\n'"  請先手動把 .statusLine.command 改回你原本的 statusline 指令，再重跑這支腳本。"
    ;;
esac

# 沒有 statusline 也可以裝：wrapper 只負責鏡射，不輸出任何東西。
if [ -z "$ORIGINAL" ]; then
  echo "· 你目前沒有設定 statusline，wrapper 只會做鏡射、不顯示任何內容"
fi

# ─────────────────────────────────────────────── 產生 wrapper

# 原本的指令要以「單引號字串」的形式寫進 wrapper：
#   - 不能讓它在產生 wrapper 的當下被展開（那會變成壞掉的賦值）
#   - 也不能用 printf %q，那會把 ~ 跳脫掉，eval 時就不再展開成家目錄
# 所以只處理單引號本身： ' → '\''
ESCAPED=${ORIGINAL//\'/\'\\\'\'}

cat > "$WRAPPER" <<WRAPPER_EOF
#!/bin/bash
# 由 ai-meter 的 setup-statusline.sh 產生。反安裝：scripts/setup-statusline.sh --uninstall
#
# 把 rate_limits（含 resets_at）鏡射到 rate-limits.json，然後原封不動轉交原本的 statusline。
#
# 這層必須「絕不擋路」：鏡射失敗也一定要把 payload 交出去，
# 否則 statusline 會整條消失，而使用者只會覺得 Claude Code 壞了。
set -uo pipefail

MIRROR="\$HOME/.claude/rate-limits.json"
input=\$(cat)

# 寫暫存再 mv，避免讀的人剛好讀到寫到一半的檔。
{
  printf '%s' "\$input" | jq -c '{
    five_hour: .rate_limits.five_hour,
    seven_day: .rate_limits.seven_day,
    captured_at: (now | floor)
  }' > "\$MIRROR.tmp" 2>/dev/null && mv -f "\$MIRROR.tmp" "\$MIRROR"
} || rm -f "\$MIRROR.tmp"

INNER='${ESCAPED}'
if [ -n "\$INNER" ]; then
  printf '%s' "\$input" | eval "\$INNER"
fi
WRAPPER_EOF

chmod +x "$WRAPPER"
ok "已產生 $WRAPPER"

# ─────────────────────────────────────────────── 驗證：輸出必須一模一樣

PAYLOAD='{"model":{"display_name":"Probe"},"context_window":{"remaining_percentage":50},"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1700000000},"seven_day":{"used_percentage":2,"resets_at":1700000000}},"workspace":{"current_dir":"'"$HOME"'"},"cwd":"'"$HOME"'"}'

BEFORE=$(mktemp); AFTER=$(mktemp)
if [ -n "$ORIGINAL" ]; then
  printf '%s' "$PAYLOAD" | eval "$ORIGINAL" >"$BEFORE" 2>&1
fi
printf '%s' "$PAYLOAD" | bash "$WRAPPER" >"$AFTER" 2>&1

if ! diff -q "$BEFORE" "$AFTER" >/dev/null; then
  rm -f "$WRAPPER"
  echo "── 原本 ──"; cat "$BEFORE"
  echo "── 經過 wrapper ──"; cat "$AFTER"
  rm -f "$BEFORE" "$AFTER"
  die "wrapper 會改變 statusline 的輸出，已中止並移除 wrapper。settings.json 未被修改。"
fi
rm -f "$BEFORE" "$AFTER"
ok "輸出比對一致，statusline 不會有任何變化"

[ -f "$MIRROR" ] && ok "鏡射檔已產生 $MIRROR"

# ─────────────────────────────────────────────── 改 settings.json

BACKUP="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"
ok "已備份 $BACKUP"

# aiMeterWrapped 記住原本的指令，反安裝時才還得回去。
jq --arg w "bash $WRAPPER" --arg o "$ORIGINAL" \
  '.statusLine.type = "command" | .statusLine.command = $w | .statusLine.aiMeterWrapped = $o' \
  "$SETTINGS" > "$SETTINGS.tmp"

if ! jq empty "$SETTINGS.tmp" 2>/dev/null; then
  rm -f "$SETTINGS.tmp"
  die "產生的 settings.json 不是合法 JSON，已中止（原檔未動）"
fi
mv -f "$SETTINGS.tmp" "$SETTINGS"

ok "settings.json 已指向 wrapper"
echo
echo "重置倒數會在下一次 Claude Code session 跑 statusline 之後出現。"
echo "驗證：make probe"
