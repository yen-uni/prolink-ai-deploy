#!/usr/bin/env bash
# wizard/lib/state.sh — 狀態管理
# 持久化到 /home/yen/.wizard_state.json
# 支援 [B] 上一步 + Ctrl+C 後續跑
# Source-only; do not run directly.

STATE_FILE="${WIZARD_STATE_FILE:-/home/yen/.wizard_state.json}"

# ─── 初始化 ────────────────────────────────────────
state_init() {
  if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" <<EOF
{
  "version": "fp102",
  "current_step": 1,
  "started_at": "$(date -Iseconds)",
  "data": {}
}
EOF
  fi
}

# ─── 讀 ──────────────────────────────────────────
# state_get <key.path> (jq path, 不含開頭的 .data)
state_get() {
  local key="$1"
  jq -r ".data.${key} // empty" "$STATE_FILE" 2>/dev/null
}

state_get_current_step() {
  jq -r '.current_step // 1' "$STATE_FILE" 2>/dev/null
}

# ─── 寫 ──────────────────────────────────────────
# state_set <key> <value> (string)
state_set() {
  local key="$1" value="$2"
  local tmp
  tmp="$(mktemp)"
  jq --arg k "$key" --arg v "$value" '.data[$k] = $v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_set_current_step() {
  local step="$1"
  local tmp
  tmp="$(mktemp)"
  jq --argjson s "$step" '.current_step = $s' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ─── reset (清狀態, 重新跑) ────────────────────────
state_reset() {
  rm -f "$STATE_FILE"
  state_init
}

# ─── dump (debug / handoff doc 用) ─────────────────
state_dump() {
  cat "$STATE_FILE"
}

state_dump_data() {
  jq '.data' "$STATE_FILE"
}

# ─── 註冊 step 列表 (給 wizard 主 loop) ────────────
# STEP_LIST 由主腳本定義為 array
state_run_steps() {
  local total="${#STEP_LIST[@]}"
  local cur
  cur="$(state_get_current_step)"
  while [ "$cur" -le "$total" ]; do
    local fn="${STEP_LIST[$((cur - 1))]}"
    prompt_progress "$cur" "$total" "$fn"
    if "$fn"; then
      cur=$((cur + 1))
      state_set_current_step "$cur"
    else
      local rc=$?
      if [ "$rc" -eq 10 ]; then
        # back
        if [ "$cur" -gt 1 ]; then
          cur=$((cur - 1))
          state_set_current_step "$cur"
          prompt_warn "返回上一步: ${STEP_LIST[$((cur - 1))]}"
        else
          prompt_warn "已在第 1 步,無法再退"
        fi
      else
        prompt_fail_with_hint "$cur" "step function 回 rc=$rc" "修正後重跑 wizard,會從 step $cur 續"
        return "$rc"
      fi
    fi
  done
  return 0
}
