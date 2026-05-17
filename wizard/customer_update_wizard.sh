#!/usr/bin/env bash
# customer_update_wizard.sh — ProLink AI 升級精靈
#
# 用法:
#   cd ~/prolink-ai-deploy
#   bash wizard/customer_update_wizard.sh
#
# 流程:
#   1. 讀本機 backend container 目前 image tag
#   2. 查 GCP Artifact Registry 最新 release tag
#   3. 比對 → 顯示 whiptail 升級確認對話框
#   4. docker compose pull → up -d → healthcheck
#   5. pull 失敗 (401/403 = 月費停繳) → whiptail msgbox 顯示「請聯繫」訊息
#
# TEST_MODE=1 走 dummy (CI / unit smoke)
# TEST_FAIL_PULL=1 模擬 401/403 (license 失效 path)
#
# FP104 (2026-05-18): 客戶升級精靈、對齊 deploy wizard whiptail TUI

set -uo pipefail

WIZARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$WIZARD_DIR/.." && pwd)"

# shellcheck source=lib/prompt.sh
source "$WIZARD_DIR/lib/prompt.sh"
# shellcheck source=lib/state.sh
source "$WIZARD_DIR/lib/state.sh"
# shellcheck source=lib/update.sh
source "$WIZARD_DIR/lib/update.sh"

DATE="$(date +%Y%m%d)"
LOG_FILE="/home/yen/update_run_${DATE}.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# ─── License 失效 msgbox ─────────────────────────────
show_license_expired() {
  prompt_msgbox "ProLink AI 升級服務 — 授權失效

您的升級授權已停止、目前系統會繼續使用既有版本運行。

如需取得最新功能、請聯繫:
LINE ID: 0919yen"
  prompt_warn "升級已取消 — 既有部署不受影響、可繼續使用"
}

# ─── 主流程 ──────────────────────────────────────────
main() {
  prompt_box "ProLink AI 升級精靈"
  wizard_check_prereq

  # Step 1: 偵測現有部署
  prompt_section "Step 1/4 — 偵測本機 backend image"
  local cur
  cur="$(detect_current_tag)"
  if [ -z "$cur" ]; then
    prompt_error "找不到 backend container (uni-ai-backend)"
    prompt_hint "請先用 customer_deploy_wizard.sh 部署、再執行升級"
    return 1
  fi
  prompt_ok "目前版本: $cur"

  # Step 2: 查 Registry 最新
  prompt_section "Step 2/4 — 查 Registry 最新 release"
  local latest
  latest="$(fetch_latest_release_tag)"
  if [ -z "$latest" ]; then
    prompt_error "查 Registry tag 失敗 (可能未授權或網路問題)"
    prompt_hint "確認 gcloud auth + docker 已 login Artifact Registry"
    show_license_expired
    return 1
  fi
  prompt_ok "Registry 最新: $latest"

  # Step 3: 比對 + 確認
  prompt_section "Step 3/4 — 升級確認"
  if ! needs_upgrade "$cur" "$latest"; then
    prompt_ok "已是最新版本 ($cur) — 無需升級"
    return 0
  fi
  if ! prompt_confirm "升級 $cur → $latest、確認執行?"; then
    prompt_info "使用者取消升級"
    return 0
  fi

  # Step 4: pull + up + healthcheck
  prompt_section "Step 4/4 — 升級執行"
  prompt_info "docker compose pull..."
  local rc
  update_pull_image "$REPO_DIR"
  rc=$?
  if [ "$rc" -eq 41 ]; then
    prompt_error "docker pull 回 401/403 — 升級授權失效"
    show_license_expired
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    prompt_error "docker compose pull 失敗 (exit=$rc)"
    prompt_hint "查 docker compose pull 手動輸出、或 docker login registry 後重試"
    return 1
  fi
  prompt_ok "image pull OK"

  prompt_info "docker compose up -d..."
  if ! update_compose_up "$REPO_DIR"; then
    prompt_error "docker compose up -d 失敗"
    prompt_hint "docker compose logs 查 container 為何起不來"
    return 1
  fi
  prompt_ok "container 已啟動"

  prompt_info "等 backend healthz..."
  if ! update_healthcheck "http://localhost:8003/"; then
    prompt_warn "healthcheck 未通 (30s 內) — 請手動 docker compose logs 查"
    return 1
  fi
  prompt_ok "backend healthcheck PASS"

  prompt_box "升級完成 — $cur → $latest"
  prompt_info "建議: 進 WP admin 跑一次 dogfood 確認功能正常"
}

# ─── entry ─────────────────────────────────────────
{
  main "$@"
  exit_code=$?
} 2>&1 | tee -a "$LOG_FILE"

exit "${exit_code:-0}"
