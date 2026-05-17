#!/usr/bin/env bash
# wizard/lib/update.sh — 升級邏輯 helper
# Source-only; do not run directly.
#
# 設計:
# - 讀本機 backend container image (docker inspect)
# - 查 GCP Artifact Registry 最新 release tag (gcloud artifacts docker tags list)
# - docker compose pull → up -d → healthcheck
# - pull 失敗 (401/403) → return 特定 exit code,caller 用 whiptail msgbox 顯示
#
# 環境變數:
#   TEST_MODE=1            走 dummy (CI / unit smoke)
#   TEST_FAIL_PULL=1       模擬 docker pull 401/403 (TEST_MODE 才生效)

# ─── 偵測本機目前 backend image tag ────────────────
# 找 container "uni-ai-backend" → docker inspect → image tag
# 找不到 container → 回空字串 (caller 視為「無現有部署」)
detect_current_tag() {
  if [ "${TEST_MODE:-0}" = "1" ]; then
    printf '%s' "release-v0.9"
    return 0
  fi
  local img
  img="$(docker inspect uni-ai-backend --format '{{.Config.Image}}' 2>/dev/null || true)"
  if [ -z "$img" ]; then
    return 0
  fi
  # image format: asia-east1-docker.pkg.dev/.../uni-ai-backend:release-v1.0
  printf '%s' "${img##*:}"
}

# ─── 查 Registry 最新 release tag ──────────────────
# 過濾 tag~^release-v[0-9] 並按版本 sort,取最大
fetch_latest_release_tag() {
  if [ "${TEST_MODE:-0}" = "1" ]; then
    printf '%s' "release-v1.0"
    return 0
  fi
  local registry="${1:-asia-east1-docker.pkg.dev/ecstatic-emblem-490504-d5/uni-ai-backend/uni-ai-backend}"
  local tags
  tags="$(gcloud artifacts docker tags list "$registry" --filter="tag~^release-v[0-9]" --format="value(tag.basename())" 2>/dev/null || true)"
  if [ -z "$tags" ]; then
    return 1
  fi
  # 版本排序: release-v1.10 > release-v1.2 > release-v1.0
  printf '%s\n' "$tags" | sed 's/^release-v//' | sort -V | tail -1 | sed 's/^/release-v/'
}

# ─── 版本比較 (semver-ish) ─────────────────────────
# return 0 if $1 < $2 (升級可用)
# return 1 otherwise (已是最新 / 自定義 tag)
needs_upgrade() {
  local cur="$1" latest="$2"
  [ -z "$cur" ] && return 0
  [ "$cur" = "$latest" ] && return 1
  # 純字串比較 fallback (release-v 開頭才比)
  case "$cur" in release-v*) ;; *) return 1 ;; esac
  case "$latest" in release-v*) ;; *) return 1 ;; esac
  local cur_v="${cur#release-v}" latest_v="${latest#release-v}"
  # sort -V 後較小者排前; 如果 cur 排前 = cur 較舊 = 需升級
  local first
  first="$(printf '%s\n%s\n' "$cur_v" "$latest_v" | sort -V | head -1)"
  [ "$first" = "$cur_v" ] && [ "$cur_v" != "$latest_v" ]
}

# ─── docker compose pull ───────────────────────────
# 失敗 → return 41 (401/403 auth) 或 42 (其他錯)
# caller 用這個 exit code 走 license msgbox path
update_pull_image() {
  local compose_dir="${1:-.}"
  if [ "${TEST_MODE:-0}" = "1" ]; then
    if [ "${TEST_FAIL_PULL:-0}" = "1" ]; then
      prompt_info "[TEST] docker compose pull → 401/403 (TEST_FAIL_PULL=1)"
      return 41
    fi
    prompt_info "[TEST] docker compose pull (dummy)"
    return 0
  fi
  local out
  out="$( ( cd "$compose_dir" && docker compose pull 2>&1 ) )"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    # 401 / 403 / Unauthorized / denied
    if printf '%s' "$out" | grep -qE "401|403|Unauthorized|unauthorized|denied|forbidden"; then
      return 41
    fi
    return 42
  fi
  return 0
}

# ─── docker compose up + healthcheck ───────────────
update_compose_up() {
  local compose_dir="${1:-.}"
  if [ "${TEST_MODE:-0}" = "1" ]; then
    prompt_info "[TEST] docker compose up -d (dummy)"
    return 0
  fi
  ( cd "$compose_dir" && docker compose up -d )
}

# ─── healthcheck (backend /healthz) ────────────────
update_healthcheck() {
  if [ "${TEST_MODE:-0}" = "1" ]; then
    prompt_info "[TEST] healthcheck backend /healthz → 200 (dummy)"
    return 0
  fi
  local url="${1:-http://localhost:8003/}"
  local i
  for i in 1 2 3 4 5 6; do
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}
