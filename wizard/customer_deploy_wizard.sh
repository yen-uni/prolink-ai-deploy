#!/usr/bin/env bash
# wizard/customer_deploy_wizard.sh — ProLink AI 客戶部署 wizard (FP102 Phase A)
# Usage:
#   bash wizard/customer_deploy_wizard.sh             # 真實模式
#   TEST_MODE=1 bash wizard/customer_deploy_wizard.sh # 全外呼 echo dummy
#
# 狀態檔: /home/yen/.wizard_state.json (Ctrl+C 後再跑自動續)
# Log:    /home/yen/wizard_run_${DATE}.log

set -uo pipefail

# ─── 路徑 ─────────────────────────────────────────
WIZARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$WIZARD_DIR/.." && pwd)"
DATE="$(date +%Y%m%d)"
LOG_FILE="${WIZARD_LOG_FILE:-/home/yen/wizard_run_${DATE}.log}"

# ─── source libs ─────────────────────────────────
# shellcheck disable=SC1091
source "$WIZARD_DIR/lib/prompt.sh"
# shellcheck disable=SC1091
source "$WIZARD_DIR/lib/state.sh"
# shellcheck disable=SC1091
source "$WIZARD_DIR/lib/validate.sh"

# ─── log redirect (tee 同時看畫面) ─────────────────
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

prompt_box "ProLink AI 客戶部署 wizard (FP102) — $(date)"
prompt_info "log file: $LOG_FILE"
if [ "${TEST_MODE:-0}" = "1" ]; then
  prompt_warn "TEST_MODE=1 — 所有外呼 (gcloud/OpenAI/Anthropic/docker/mysql/certbot/LINE) 將 echo dummy 不真實執行"
fi

state_init

# FP103-A: 檢查 whiptail (沒裝就問是否 install, 不 hard fail)
wizard_check_prereq

# ─── Step 函式 (return 0=PASS, 10=back, 1=fail) ────

step01_gcp_project() {
  prompt_section "Step 1/17 — GCP 專案 ID"
  local pid
  prompt_ask pid "請輸入客戶 GCP project ID" "$(state_get gcp_project)" "dummy-gcp-project" || return $?
  if ! validate_gcp_project "$pid"; then
    prompt_fail_with_hint 1 "gcloud projects describe $pid 失敗" "確認 project 存在 + gcloud 已 auth (gcloud auth login)"
    return 1
  fi
  state_set gcp_project "$pid"
  prompt_ok "GCP project: $pid"
}

step02_vm_size() {
  prompt_section "Step 2/17 — VM 機型確認"
  local pid zone name
  pid="$(state_get gcp_project)"
  prompt_ask zone "VM zone" "$(state_get gcp_zone)" "asia-east1-b" || return $?
  prompt_ask name "VM instance name" "$(state_get gcp_vm)" "uni-ai-vm" || return $?
  if ! validate_vm_size "$pid" "$zone" "$name"; then
    prompt_fail_with_hint 2 "VM $name 不存在或機型 <n2-standard-2" "gcloud compute instances list --project=$pid 看實際狀況"
    return 1
  fi
  state_set gcp_zone "$zone"
  state_set gcp_vm "$name"
  prompt_ok "VM $name (zone=$zone) ≥n2-standard-2"
}

step03_brand_name() {
  prompt_section "Step 3/17 — 品牌名稱 (中英)"
  local brand_zh brand_en
  prompt_ask brand_zh "品牌中文" "$(state_get brand_zh)" "示範客戶" || return $?
  prompt_ask brand_en "品牌英文 (a-z0-9-)" "$(state_get brand_en)" "demo-client" || return $?
  state_set brand_zh "$brand_zh"
  state_set brand_en "$brand_en"
  if ! wp_option_update "uni_ai_brand_system_name" "$brand_zh"; then
    prompt_fail_with_hint 3 "wp option update 失敗" "確認 WordPress 已啟動 + wp-cli 可用"
    return 1
  fi
  prompt_ok "品牌: $brand_zh / $brand_en"
}

step04_db_conn() {
  prompt_section "Step 4/17 — DB 連線"
  local host port user pass db
  prompt_ask host "DB host"     "$(state_get db_host)" "127.0.0.1" || return $?
  prompt_ask port "DB port"     "$(state_get db_port)" "3306"      || return $?
  prompt_ask user "DB user"     "$(state_get db_user)" "uni_rw"    || return $?
  prompt_ask pass "DB password (TEST 自動帶 dummy)" "" "dummy-db-pw" || return $?
  prompt_ask db   "DB name"     "$(state_get db_name)" "uni_db"    || return $?
  if ! validate_db "$host" "$port" "$user" "$pass" "$db"; then
    prompt_fail_with_hint 4 "mysql SELECT 1 失敗" "確認 DB 已開 + user/pass/host/port/db 對得上 + GRANT 完成"
    return 1
  fi
  state_set db_host "$host"
  state_set db_port "$port"
  state_set db_user "$user"
  state_set db_name "$db"
  # 注意: pass 不寫 state (避免明文), 直接寫 .env
  write_env_kv "$REPO_DIR/.env" "DB_PASSWORD" "$pass"
  prompt_ok "DB $user@$host:$port/$db SELECT 1 OK"
}

step05_openai_key() {
  prompt_section "Step 5/17 — OpenAI API Key"
  local key
  prompt_ask key "OpenAI API key (sk-...)" "" "sk-dummy-openai-test" || return $?
  if ! validate_openai_key "$key"; then
    prompt_fail_with_hint 5 "curl OpenAI /v1/models 不是 200" "確認 key 有效 + 帳號有額度 + 網路可達 api.openai.com"
    return 1
  fi
  write_env_kv "$REPO_DIR/.env" "OPENAI_API_KEY" "$key"
  state_set openai_key_set "1"
  prompt_ok "OpenAI key 驗證 PASS"
}

step06_anthropic_key() {
  prompt_section "Step 6/17 — Anthropic API Key (選填)"
  local key
  prompt_ask key "Anthropic API key (空白 = 跳過)" "" "sk-ant-dummy" || return $?
  if [ -z "$key" ]; then
    prompt_warn "Anthropic key 留空 — 客戶將只用 OpenAI"
    state_set anthropic_key_set "0"
    return 0
  fi
  if ! validate_anthropic_key "$key"; then
    prompt_fail_with_hint 6 "Anthropic messages endpoint 失敗" "確認 key 有效 + 網路可達 api.anthropic.com"
    return 1
  fi
  write_env_kv "$REPO_DIR/.env" "ANTHROPIC_API_KEY" "$key"
  state_set anthropic_key_set "1"
  prompt_ok "Anthropic key 驗證 PASS"
}

step07_hmac_secret() {
  prompt_section "Step 7/17 — HMAC Secret 自動生成"
  local secret
  secret="$(generate_hmac_secret)"
  if [ -z "$secret" ]; then
    prompt_fail_with_hint 7 "openssl rand 失敗" "確認 openssl 已裝 (apt install openssl)"
    return 1
  fi
  write_env_kv "$REPO_DIR/.env" "HMAC_SECRET" "$secret"
  state_set hmac_secret_set "1"
  prompt_ok "HMAC secret 32-byte base64 寫入 .env"
}

step08_logo_upload() {
  prompt_section "Step 8/17 — Logo 上傳"
  local src dst
  prompt_ask src "Logo 檔案路徑 (PNG)" "$(state_get logo_src)" "/tmp/dummy-logo.png" || return $?
  dst="/var/www/html/wp-content/uploads/uni-ai-logo.png"
  if ! upload_logo "$src" "$dst"; then
    prompt_fail_with_hint 8 "logo 複製失敗" "確認 $src 存在 + $dst 父目錄可寫"
    return 1
  fi
  state_set logo_src "$src"
  prompt_ok "Logo → $dst"
}

step09_docker_pull() {
  prompt_section "Step 9/17 — Docker pull (latest image)"
  if ! docker_pull "$REPO_DIR"; then
    prompt_fail_with_hint 9 "docker compose pull 失敗" "確認 docker 已 login registry + docker-compose.yml 在 $REPO_DIR"
    return 1
  fi
  prompt_ok "docker compose pull OK"
}

step10_docker_up() {
  prompt_section "Step 10/17 — Docker compose up + healthcheck wait"
  if ! docker_up "$REPO_DIR"; then
    prompt_fail_with_hint 10 "docker compose up -d 失敗" "docker compose logs 查 container 為何起不來"
    return 1
  fi
  if [ "${TEST_MODE:-0}" != "1" ]; then
    prompt_info "等 30s 讓 backend / WP 起來..."
    sleep 30
  fi
  prompt_ok "docker compose up -d OK"
}

step11_healthcheck() {
  prompt_section "Step 11/17 — Healthcheck (backend / WP / DB)"
  local host port user pass
  host="$(state_get db_host)"
  port="$(state_get db_port)"
  user="$(state_get db_user)"
  pass="${WIZARD_DB_PASSWORD:-dummy-db-pw}"
  local ok=0
  healthcheck_backend "http://localhost:8003/healthz" && { prompt_ok "backend /healthz 200"; } || { prompt_warn "backend /healthz 不是 200"; ok=1; }
  healthcheck_wp "http://localhost/wp-json" && { prompt_ok "WP /wp-json 通"; } || { prompt_warn "WP /wp-json 不通"; ok=1; }
  healthcheck_db_ping "$host" "$port" "$user" "$pass" && { prompt_ok "DB ping alive"; } || { prompt_warn "DB ping 失敗"; ok=1; }
  if [ "$ok" -ne 0 ]; then
    prompt_fail_with_hint 11 "其中一個 healthcheck 沒通" "docker compose logs / mysql -h$host -P$port -u$user -p 手動驗"
    return 1
  fi
  prompt_ok "三端 healthcheck 全綠"
}

# ─── Phase B: SSL + LINE + 知識庫 + WP admin ───────

step12_ssl() {
  prompt_section "Step 12/17 — 自動 SSL (Let's Encrypt)"
  local domain email
  prompt_ask domain "客戶 domain (e.g. ai.client.com)" "$(state_get domain)" "demo.example.com" || return $?
  prompt_ask email  "certbot 通知 email" "$(state_get cert_email)" "ops@example.com" || return $?
  if ! provision_ssl "$domain" "$email"; then
    prompt_fail_with_hint 12 "certbot --nginx 失敗" "確認 domain DNS A record 指向本機 + nginx 已起 + port 80/443 開"
    return 1
  fi
  state_set domain "$domain"
  state_set cert_email "$email"
  prompt_ok "SSL for $domain 已簽發"
}

step13_line_webhook() {
  prompt_section "Step 13/17 — LINE webhook 接通"
  local token secret
  prompt_ask token  "LINE Channel access token"   "" "DUMMY_LINE_TOKEN" || return $?
  prompt_ask secret "LINE Channel secret"         "" "DUMMY_LINE_SECRET" || return $?
  if ! validate_line_channel "$token"; then
    prompt_fail_with_hint 13 "LINE /v2/bot/info 失敗" "確認 token 有效 + LINE channel 已建立"
    return 1
  fi
  wp_option_update "uni_ai_line_channel_access_token" "$token"
  wp_option_update "uni_ai_line_channel_secret" "$secret"
  state_set line_set "1"
  prompt_ok "LINE webhook 接通"
}

step14_kb_ingest() {
  prompt_section "Step 14/17 — 知識庫匯入 (17 PDF)"
  local folder svc
  prompt_ask folder "PDF 資料夾路徑" "$(state_get kb_folder)" "/home/yen/kb_pdfs" || return $?
  svc="$(_detect_backend_service "$REPO_DIR")"
  if [ -z "$svc" ]; then
    prompt_fail_with_hint 14 "auto-detect backend service 失敗" "docker compose ps --services 看實際 service 名"
    return 1
  fi
  state_set backend_service "$svc"
  if ! ingest_pdfs "$folder" "$REPO_DIR" "$svc"; then
    prompt_fail_with_hint 14 "ingest_pdfs.py 失敗" "docker compose exec $svc python /app/scripts/ingest_pdfs.py --folder $folder 手動跑看 log"
    return 1
  fi
  state_set kb_folder "$folder"
  prompt_ok "知識庫匯入 OK (backend service=$svc)"
}

step15_wp_admin() {
  prompt_section "Step 15/17 — WP admin 首次登入帳號"
  local user email pw
  prompt_ask user  "WP admin username" "$(state_get wp_admin_user)" "uni_admin" || return $?
  prompt_ask email "WP admin email"    "$(state_get wp_admin_email)" "admin@example.com" || return $?
  pw="$(create_wp_admin "$user" "$email")"
  if [ -z "$pw" ]; then
    prompt_fail_with_hint 15 "wp user create 失敗" "docker compose exec wordpress wp user list --allow-root 手動驗"
    return 1
  fi
  state_set wp_admin_user "$user"
  state_set wp_admin_email "$email"
  state_set wp_admin_pw "$pw"
  prompt_box "WP admin 帳號建立完成"
  prompt_ok "Username: $user"
  prompt_ok "Password: $pw"
  prompt_warn "請立刻存入密碼管理員 (1Password / Bitwarden 等)、本訊息不會再顯示"
  prompt_warn "提示: 此密碼亦寫入 handoff doc、客戶 IT 應在登入後立即改密碼"
  # FP103-A: Debian-installer 風 msgbox — 在 TUI 對話框再強調一次
  prompt_msgbox "WP admin 帳號建立完成

  Username: $user
  Password: $pw

請立刻存入密碼管理員 (1Password / Bitwarden 等)
此密碼亦寫入 handoff doc、客戶 IT 應在登入後立即改密碼"
}

# ─── Phase C: handoff + dogfood ────────────────────

step16_handoff_doc() {
  prompt_section "Step 16/17 — 產 handoff 文件"
  local brand_zh brand_en
  brand_zh="$(state_get brand_zh)"
  brand_en="$(state_get brand_en)"
  local out="/home/yen/CUSTOMER_HANDOFF_${brand_en}_${DATE}.md"

  local pid zone vm host port user db domain wp_user wp_pw backend_svc
  pid="$(state_get gcp_project)"
  zone="$(state_get gcp_zone)"
  vm="$(state_get gcp_vm)"
  host="$(state_get db_host)"
  port="$(state_get db_port)"
  user="$(state_get db_user)"
  db="$(state_get db_name)"
  domain="$(state_get domain)"
  wp_user="$(state_get wp_admin_user)"
  wp_pw="$(state_get wp_admin_pw)"
  backend_svc="$(state_get backend_service)"
  [ -z "$backend_svc" ] && backend_svc="backend"

  cat > "$out" <<EOF
# ${brand_zh} (${brand_en}) — ProLink AI 部署 Handoff
產生時間: $(date -Iseconds)

## 1. GCP / VM
- Project: ${pid}
- Zone:    ${zone}
- VM:      ${vm}
- SSH:     \`gcloud compute ssh ${vm} --project=${pid} --zone=${zone}\`

## 2. Endpoint URL
- WordPress:    https://${domain}/
- Backend API:  https://${domain}/api/v1/ask
- LINE webhook: https://${domain}/wp-json/uni-ai/v1/line/webhook
- SSL: Let's Encrypt (auto-renew via certbot timer)

## 3. DB
- Host: ${host}:${port}
- User: ${user}
- DB:   ${db}
- 密碼存於 .env (DB_PASSWORD) — 請勿擅自更動

## 4. WP Admin
- Username: ${wp_user}
- 初始密碼: ${wp_pw}
- 登入後請立刻改密碼

## 5. 常用維運指令
\`\`\`bash
# SSH 進 VM
gcloud compute ssh ${vm} --project=${pid} --zone=${zone}

# 看後端 log (backend service auto-detect 於部署當下)
cd ~/uni-deploy && docker compose logs -f ${backend_svc}

# 重啟
cd ~/uni-deploy && docker compose restart

# 升級 image
cd ~/uni-deploy && docker compose pull && docker compose up -d

# 知識庫補檔 (backend service auto-detect 於部署當下)
docker compose exec ${backend_svc} python /app/scripts/ingest_pdfs.py --folder /path/to/new_pdfs

# DB 連線測試
mysql -h ${host} -P ${port} -u ${user} -p ${db} -e "SELECT 1"

# 重簽 SSL (自動 renew 失敗時)
sudo certbot renew --nginx
\`\`\`

## 6. 客服 / 技術支援
- ProLink AI 技術支援: LINE ID: 0919yen
- Yen 直線: (填入)
- GitHub repo (內部): https://github.com/yen-uni/rag

## 7. 注意事項
- HMAC secret / DB password / OpenAI key 全部存於 .env,不可進 git
- LINE channel token 存於 wp_options 加密欄
- 首次登入後請立刻改 WP admin 密碼
- 客戶若需新增管理員 → WP admin 後台 -> 員工管理

## 8. 第一次驗收 — 客戶 IT 自行 LINE 試問
部署 wizard 內部已用 backend API 驗 RAG chain 通,**但 LINE webhook 必須由真人從 LINE App 主動觸發才能完整驗收** (wizard 無法模擬 user 輸入)。

**請客戶 IT 在交付前完成以下手動驗收**:
1. 用手機 LINE 加入 official account (掃 QR / 搜 LINE ID — 由客戶提供)
2. 傳一句測試訊息:「我手上有哪些案件」或「測試」
3. 預期: 30 秒內收到回應 (含案件清單或測試確認)
4. 若無回應:
   - 確認 LINE Developer Console 的 webhook URL 設為 \`https://${domain}/wp-json/uni-ai/v1/line/webhook\`
   - 確認 webhook verify 按鈕回 \`Success\`
   - 看後端 log: \`docker compose logs -f ${backend_svc} | grep -i line\`
5. 驗收通過後請回報ProLink AI 技術支援、正式交付

**為什麼這步需要真人**: LINE 平台不允許 backend 模擬 user 訊息、必須真實 LINE 帳號 push 才會觸發 webhook。
EOF

  if [ ! -s "$out" ]; then
    prompt_fail_with_hint 16 "handoff doc 寫入失敗" "看 $out 父目錄權限"
    return 1
  fi
  state_set handoff_doc "$out"
  prompt_ok "Handoff doc: $out"
}

step17_dogfood() {
  prompt_section "Step 17/17 — 第一次 dogfood (LINE webhook 模擬)"
  local resp
  resp="$(dogfood_line_webhook 'http://localhost:8003/api/v1/ask' '我手上有哪些案件')"
  if [ -z "$resp" ]; then
    prompt_fail_with_hint 17 "dogfood response 空" "curl -v 手動打 backend /api/v1/ask 看 stack"
    return 1
  fi
  state_set dogfood_response "$resp"
  prompt_ok "Dogfood OK — response: ${resp:0:120}"
}

# ─── STEP_LIST + 主 loop ──────────────────────────
# Phase A: 11 base + Phase B: 4 (SSL/LINE/KB/WP admin) + Phase C: 2 (handoff/dogfood) = 17
STEP_LIST=(
  step01_gcp_project
  step02_vm_size
  step03_brand_name
  step04_db_conn
  step05_openai_key
  step06_anthropic_key
  step07_hmac_secret
  step08_logo_upload
  step09_docker_pull
  step10_docker_up
  step11_healthcheck
  step12_ssl
  step13_line_webhook
  step14_kb_ingest
  step15_wp_admin
  step16_handoff_doc
  step17_dogfood
)

if [ "${WIZARD_STEPS_ONLY:-0}" = "1" ]; then
  # 只跑前 N 步 (phase A smoke 用)
  STEP_LIST=("${STEP_LIST[@]:0:${WIZARD_MAX_STEP:-17}}")
fi

# 上次跑到 step > total 算上次完成 → 重新從 1 開始
total="${#STEP_LIST[@]}"
cur="$(state_get_current_step)"
if [ "$cur" -gt "$total" ]; then
  prompt_info "上次已跑完全部 $total 步 — reset state 重新開始"
  state_reset
fi

trap 'prompt_warn "Ctrl+C 中斷 — 狀態已存 $STATE_FILE,下次跑會續"; exit 130' INT

if state_run_steps; then
  prompt_box "WIZARD 全綠 — 所有 ${#STEP_LIST[@]} 步 PASS"
  # 跑完 unset TEST_MODE (per brief: 不留 export)
  if [ "${TEST_MODE:-0}" = "1" ]; then
    unset TEST_MODE
    prompt_info "TEST_MODE 已 unset"
  fi
  exit 0
else
  rc=$?
  prompt_error "WIZARD 中斷於 rc=$rc — 修正後重跑會從斷點續"
  exit "$rc"
fi
