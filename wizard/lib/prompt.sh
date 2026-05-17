#!/usr/bin/env bash
# wizard/lib/prompt.sh — UI 渲染 (進度條 / 顏色 / 對話框)
# FP103 Phase A: whiptail TUI 升級 (Debian-style installer)
#   - prompt_ask / prompt_confirm / prompt_msgbox 優先用 whiptail
#   - whiptail 不可用 → fallback 純文字 read -p (不 hard fail)
#   - TEST_MODE=1 全 bypass (echo dummy / msgbox 印一行)
# Source-only; do not run directly.

# ─── 顏色 ─────────────────────────────────────────
if [ -t 1 ]; then
  CLR_RESET="\033[0m"
  CLR_BOLD="\033[1m"
  CLR_RED="\033[31m"
  CLR_GREEN="\033[32m"
  CLR_YELLOW="\033[33m"
  CLR_BLUE="\033[34m"
  CLR_CYAN="\033[36m"
  CLR_GRAY="\033[90m"
else
  CLR_RESET=""; CLR_BOLD=""; CLR_RED=""; CLR_GREEN=""
  CLR_YELLOW=""; CLR_BLUE=""; CLR_CYAN=""; CLR_GRAY=""
fi

# ─── 基礎輸出 ──────────────────────────────────────
prompt_info()    { printf "%b[INFO]%b %s\n"    "$CLR_CYAN"   "$CLR_RESET" "$*"; }
prompt_ok()      { printf "%b[OK]%b %s\n"      "$CLR_GREEN"  "$CLR_RESET" "$*"; }
prompt_warn()    { printf "%b[WARN]%b %s\n"    "$CLR_YELLOW" "$CLR_RESET" "$*"; }
prompt_error()   { printf "%b[ERROR]%b %s\n"   "$CLR_RED"    "$CLR_RESET" "$*" >&2; }
prompt_hint()    { printf "%b[建議]%b %s\n"     "$CLR_BLUE"   "$CLR_RESET" "$*"; }

# 當前 step heading — whiptail 對話框 title 用
WIZARD_STEP_TITLE=""

prompt_section() {
  WIZARD_STEP_TITLE="$*"
  printf "\n%b═══ %s ═══%b\n" "$CLR_BOLD$CLR_CYAN" "$*" "$CLR_RESET"
}

# ─── 進度條 (cur/total) ────────────────────────────
prompt_progress() {
  local cur="$1" total="$2" label="$3"
  local width=30
  local filled=$(( cur * width / total ))
  local empty=$(( width - filled ))
  local bar
  bar="$(printf '█%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null)$(printf '░%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null)"
  printf "%b[%2d/%2d]%b %s %s\n" "$CLR_BOLD" "$cur" "$total" "$CLR_RESET" "$bar" "$label"
}

# ─── whiptail helpers ─────────────────────────────
# whiptail UI 需要 /dev/tty (非互動 shell / pipe / cron 沒有 → fallback 純文字)
_have_whiptail() {
  command -v whiptail >/dev/null 2>&1 && [ -r /dev/tty ] && [ -w /dev/tty ]
}

# 對話框 title: ${brand_zh|ProLink AI} 部署精靈 — ${section heading}
# step 1-2 brand_zh 還沒填 → 顯 "ProLink AI 部署精靈"
# step 3 起切到客戶品牌名
_whiptail_title() {
  local brand
  brand="$(state_get brand_zh 2>/dev/null)"
  [ -z "$brand" ] && brand="ProLink AI"
  printf '%s 部署精靈 — %s' "$brand" "${WIZARD_STEP_TITLE:-部署}"
}

# ─── 互動輸入 (TEST_MODE 自動回 dummy) ─────────────
# prompt_ask <var_name> <question> [default] [dummy_for_test]
# 回 10 = back (B / Cancel button)
prompt_ask() {
  local var="$1" question="$2" default="${3:-}" dummy="${4:-}"
  if [ "${TEST_MODE:-0}" = "1" ]; then
    local val="${dummy:-$default}"
    [ -z "$val" ] && val="test-${var}"
    printf -v "$var" '%s' "$val"
    prompt_info "[TEST] $question → $val"
    return 0
  fi
  if _have_whiptail; then
    local title tmp_val val rc
    title="$(_whiptail_title)"
    tmp_val="$(mktemp)"
    # UI 走 /dev/tty 避開外層 tee 的 stdout/stderr redirect
    # 值從 stderr 抓 (2>tmp), 不走 tee
    whiptail --title "$title" \
             --inputbox "$question\n\n(留空 = 使用預設、輸入 B = 回上一步)" \
             12 70 "$default" 2>"$tmp_val" </dev/tty >/dev/tty
    rc=$?
    val="$(cat "$tmp_val")"
    rm -f "$tmp_val"
    if [ "$rc" -ne 0 ]; then
      # Cancel button = back
      return 10
    fi
    if [ "$val" = "B" ] || [ "$val" = "b" ]; then
      return 10
    fi
    [ -z "$val" ] && val="$default"
    printf -v "$var" '%s' "$val"
    return 0
  fi
  # Fallback: 純文字 prompt (whiptail 不可用)
  local prompt_text val=""
  if [ -n "$default" ]; then
    prompt_text="$question [預設: $default] (B=上一步): "
  else
    prompt_text="$question (B=上一步): "
  fi
  read -r -p "$prompt_text" val
  if [ "$val" = "B" ] || [ "$val" = "b" ]; then
    return 10
  fi
  [ -z "$val" ] && val="$default"
  printf -v "$var" '%s' "$val"
}

# prompt_confirm <question> — Y/n, TEST 自動 Y
prompt_confirm() {
  local question="$1"
  if [ "${TEST_MODE:-0}" = "1" ]; then
    prompt_info "[TEST] $question → Y"
    return 0
  fi
  if _have_whiptail; then
    local title
    title="$(_whiptail_title)"
    whiptail --title "$title" --yesno "$question" 10 60 </dev/tty >/dev/tty 2>&1
    return $?
  fi
  local ans=""
  read -r -p "$question [Y/n]: " ans
  case "$ans" in
    n|N|no|No) return 1 ;;
    *) return 0 ;;
  esac
}

# prompt_msgbox <message> — Debian-installer 風 OK-only 對話框
# 用於 step15 顯示 WP admin 帳密這類重要資訊
prompt_msgbox() {
  local msg="$*"
  if [ "${TEST_MODE:-0}" = "1" ]; then
    prompt_info "[TEST msgbox] $(printf '%s' "$msg" | head -1)"
    return 0
  fi
  if _have_whiptail; then
    local title
    title="$(_whiptail_title)"
    whiptail --title "$title" --msgbox "$msg" 16 72 </dev/tty >/dev/tty 2>&1
    return $?
  fi
  # Fallback: 純文字 banner
  prompt_box "$(printf '%s' "$msg" | head -1)"
  printf '%s\n' "$msg"
}

# ─── 對話框 (純文字 banner) ───────────────────────
prompt_box() {
  local msg="$*"
  local len=${#msg}
  local border
  border="$(printf '─%.0s' $(seq 1 $((len + 4))))"
  printf "%b┌%s┐\n│  %s  │\n└%s┘%b\n" "$CLR_CYAN" "$border" "$msg" "$border" "$CLR_RESET"
}

# ─── 失敗 + 建議下一步 (保守: 不自動修復) ──────────
prompt_fail_with_hint() {
  local step="$1" reason="$2" hint="$3"
  prompt_error "Step $step 失敗: $reason"
  [ -n "$hint" ] && prompt_hint "建議下一步: $hint"
  prompt_hint "按 B 回上一步、或修正後重跑 wizard 自動續跑"
}

# ─── prerequisite check (一次性、wizard 啟動時呼叫) ────
# 偵測 whiptail; 沒裝就問是否 sudo apt-get install (TEST_MODE / 非互動 shell 自動 skip)
# install 失敗 / 用戶拒裝 → fallback 純文字模式 (不 hard fail)
wizard_check_prereq() {
  if command -v whiptail >/dev/null 2>&1; then
    prompt_info "TUI: whiptail ready ($(whiptail -v 2>&1 | head -1))"
    return 0
  fi
  prompt_warn "whiptail 未安裝 — 將使用純文字 prompt 模式"
  if [ "${TEST_MODE:-0}" = "1" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    prompt_info "(非互動 shell — 跳過 install prompt)"
    return 0
  fi
  local ans=""
  read -r -p "現在 sudo apt-get install whiptail (Debian/Ubuntu)? [Y/n]: " ans
  case "$ans" in
    n|N|no|No)
      prompt_info "略過 install — 純文字模式繼續"
      return 0
      ;;
  esac
  if sudo apt-get install -y whiptail </dev/null >/dev/null 2>&1; then
    prompt_ok "whiptail 安裝完成 ($(whiptail -v 2>&1 | head -1))"
  else
    prompt_warn "whiptail install 失敗 — fallback 純文字模式 (不影響功能)"
  fi
}
