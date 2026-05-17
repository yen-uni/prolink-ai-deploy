#!/usr/bin/env bash
# wizard/lib/validate.sh — 驗證函式集
# TEST_MODE=1 時所有外呼改 echo dummy,return 0
# Source-only; do not run directly.

# ─── 共用: TEST_MODE short-circuit ─────────────────
_is_test_mode() {
  [ "${TEST_MODE:-0}" = "1" ]
}

# ─── GCP project ──────────────────────────────────
validate_gcp_project() {
  local pid="$1"
  if _is_test_mode; then
    prompt_info "[TEST] gcloud projects describe $pid → OK (dummy)"
    return 0
  fi
  gcloud projects describe "$pid" >/dev/null 2>&1
}

# ─── GCP VM 機型 (n2-standard-2 以上) ──────────────
# VM machineType 字尾通常 e.g. n2-standard-2, n2d-standard-4, e2-standard-4
validate_vm_size() {
  local pid="$1" zone="$2" name="$3"
  if _is_test_mode; then
    prompt_info "[TEST] gcloud compute instances describe $name in $zone → n2-standard-2 (dummy)"
    return 0
  fi
  local mt
  mt=$(gcloud compute instances describe "$name" \
        --project="$pid" --zone="$zone" \
        --format="value(machineType)" 2>/dev/null | awk -F/ '{print $NF}')
  if [ -z "$mt" ]; then
    return 1
  fi
  # parse <fam>-<type>-<vcpu>
  local fam type vcpu
  IFS=- read -r fam type vcpu <<<"$mt"
  if [ "$type" = "standard" ] && [ "${vcpu:-0}" -ge 2 ] 2>/dev/null; then
    return 0
  fi
  prompt_warn "VM 機型 $mt 不符 ≥n2-standard-2 規格"
  return 1
}

# ─── DB 連線 ──────────────────────────────────────
validate_db() {
  local host="$1" port="$2" user="$3" pass="$4" db="$5"
  if _is_test_mode; then
    prompt_info "[TEST] mysql $user@$host:$port/$db SELECT 1 → 1 (dummy)"
    return 0
  fi
  MYSQL_PWD="$pass" mysql -h "$host" -P "$port" -u "$user" -D "$db" \
    -e "SELECT 1" >/dev/null 2>&1
}

# ─── OpenAI key ───────────────────────────────────
validate_openai_key() {
  local key="$1"
  if _is_test_mode; then
    prompt_info "[TEST] curl OpenAI /v1/models → 200 (dummy)"
    return 0
  fi
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    https://api.openai.com/v1/models \
    -H "Authorization: Bearer $key")
  [ "$code" = "200" ]
}

# ─── Anthropic key (選填) ─────────────────────────
validate_anthropic_key() {
  local key="$1"
  [ -z "$key" ] && return 0   # 選填,空跳過
  if _is_test_mode; then
    prompt_info "[TEST] curl Anthropic messages → 200 (dummy)"
    return 0
  fi
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    https://api.anthropic.com/v1/messages \
    -H "x-api-key: $key" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d '{"model":"claude-haiku-4-5","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}')
  # 401 = bad key. 200/400(model) 都算 key 通
  case "$code" in
    200|400) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── HMAC 生成 (32 byte base64) ────────────────────
generate_hmac_secret() {
  if _is_test_mode; then
    echo "DUMMY_HMAC_BASE64_32_BYTES_FOR_TEST_MODE_ONLY=="
    return 0
  fi
  openssl rand -base64 32
}

# ─── 寫 .env ──────────────────────────────────────
# write_env_kv <env_path> <key> <value>
write_env_kv() {
  local env_path="$1" key="$2" value="$3"
  if _is_test_mode; then
    prompt_info "[TEST] write_env_kv $env_path: $key=<masked>"
    return 0
  fi
  mkdir -p "$(dirname "$env_path")"
  touch "$env_path"
  if grep -q "^${key}=" "$env_path" 2>/dev/null; then
    # in-place
    local tmp; tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v}1' "$env_path" > "$tmp"
    mv "$tmp" "$env_path"
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_path"
  fi
}

# ─── Logo 上傳 (cp 至 WP uploads) ──────────────────
upload_logo() {
  local src="$1" dst="${2:-/var/www/html/wp-content/uploads/uni-ai-logo.png}"
  if _is_test_mode; then
    prompt_info "[TEST] cp $src $dst (dummy)"
    return 0
  fi
  [ -f "$src" ] || { prompt_error "logo 不存在: $src"; return 1; }
  sudo cp "$src" "$dst" 2>/dev/null || cp "$src" "$dst"
}

# ─── docker compose pull / up ─────────────────────
docker_pull() {
  local compose_dir="$1"
  if _is_test_mode; then
    prompt_info "[TEST] cd $compose_dir && docker compose pull (dummy)"
    return 0
  fi
  ( cd "$compose_dir" && docker compose pull )
}

docker_up() {
  local compose_dir="$1"
  if _is_test_mode; then
    prompt_info "[TEST] cd $compose_dir && docker compose up -d (dummy)"
    return 0
  fi
  ( cd "$compose_dir" && docker compose up -d )
}

# ─── healthcheck (3 端) ────────────────────────────
healthcheck_backend() {
  local url="${1:-http://localhost:8003/healthz}"
  if _is_test_mode; then
    prompt_info "[TEST] curl $url → 200 (dummy)"
    return 0
  fi
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  [ "$code" = "200" ]
}

healthcheck_wp() {
  local url="${1:-http://localhost/wp-json}"
  if _is_test_mode; then
    prompt_info "[TEST] curl $url → 200 (dummy)"
    return 0
  fi
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
  case "$code" in
    200|301|302) return 0 ;;
    *) return 1 ;;
  esac
}

healthcheck_db_ping() {
  local host="$1" port="$2" user="$3" pass="$4"
  if _is_test_mode; then
    prompt_info "[TEST] mysqladmin ping $host:$port → mysqld alive (dummy)"
    return 0
  fi
  MYSQL_PWD="$pass" mysqladmin ping -h "$host" -P "$port" -u "$user" 2>/dev/null \
    | grep -q "mysqld is alive"
}

# ─── wp_options 寫入 (Phase A Step 3 用) ──────────
wp_option_update() {
  local key="$1" value="$2"
  if _is_test_mode; then
    prompt_info "[TEST] wp option update $key='<masked>'"
    return 0
  fi
  docker compose exec -T wordpress wp option update "$key" "$value" --allow-root
}

# ─── Phase B: SSL (Let's Encrypt) ─────────────────
provision_ssl() {
  local domain="$1" email="$2"
  if _is_test_mode; then
    prompt_info "[TEST] certbot --nginx -d $domain --email $email (dummy)"
    return 0
  fi
  sudo certbot --nginx -d "$domain" -m "$email" --agree-tos -n
}

# ─── Phase B: LINE webhook ────────────────────────
validate_line_channel() {
  local token="$1"
  if _is_test_mode; then
    prompt_info "[TEST] curl LINE /v2/bot/info → 200 (dummy)"
    return 0
  fi
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    https://api.line.me/v2/bot/info \
    -H "Authorization: Bearer $token")
  [ "$code" = "200" ]
}

# ─── Phase B: 知識庫匯入 (PDF) ────────────────────
# auto-detect backend service name (per FP102 fp102-d: 客戶 docker service name 不可預測)
# 優先策略: exact 'backend' > 含 'backend' 或 'ai' > 列清單讓使用者選
# 所有 log 走 stderr 避免污染 $(...) 捕獲值
_detect_backend_service() {
  local compose_dir="$1"
  if _is_test_mode; then
    echo "backend"
    return 0
  fi
  local services
  services="$(cd "$compose_dir" && docker compose ps --services 2>/dev/null)"
  if [ -z "$services" ]; then
    prompt_error "docker compose ps --services 沒回任何 service (cd=$compose_dir)" >&2
    return 1
  fi
  if echo "$services" | grep -qx "backend"; then
    echo "backend"
    return 0
  fi
  local match
  match="$(echo "$services" | grep -E 'backend|ai' | head -1)"
  if [ -n "$match" ]; then
    prompt_info "auto-detect backend service: $match" >&2
    echo "$match"
    return 0
  fi
  prompt_warn "找不到含 'backend' 或 'ai' 的 service、請手選" >&2
  echo "可用 services:" >&2
  echo "$services" | nl -w2 -s'. ' >&2
  local pick=""
  read -r -p "請輸入 service 名稱: " pick </dev/tty
  echo "$pick"
}

ingest_pdfs() {
  local folder="$1" compose_dir="${2:-/home/yen/uni-deploy-20260413}" svc="${3:-backend}"
  if _is_test_mode; then
    prompt_info "[TEST] docker compose exec $svc python /app/scripts/ingest_pdfs.py --folder $folder (dummy, 17 PDF)"
    return 0
  fi
  [ -d "$folder" ] || { prompt_error "PDF 資料夾不存在: $folder"; return 1; }
  ( cd "$compose_dir" && docker compose exec -T "$svc" python /app/scripts/ingest_pdfs.py --folder "$folder" )
}

# ─── Phase B: WP admin 帳號 ───────────────────────
# stdout 只能放密碼 (用 $(...) 抓);log 走 stderr 避汙染
create_wp_admin() {
  local user="$1" email="$2"
  if _is_test_mode; then
    local pw="DUMMY_PW_TEST_$(date +%s)"
    prompt_info "[TEST] wp user create $user $email --role=administrator → pw=$pw" >&2
    echo "$pw"
    return 0
  fi
  local pw
  pw="$(openssl rand -base64 18)"
  docker compose exec -T wordpress wp user create "$user" "$email" \
    --role=administrator --user_pass="$pw" --allow-root >/dev/null 2>&1 || true
  echo "$pw"
}

# ─── Phase C: LINE webhook dogfood ────────────────
dogfood_line_webhook() {
  local url="${1:-http://localhost:8003/api/v1/ask}"
  local q="${2:-我手上有哪些案件}"
  if _is_test_mode; then
    prompt_info "[TEST] POST $url '{\"question\":\"$q\"}' → 200 dummy" >&2
    echo "{\"answer\":\"dummy reply (TEST_MODE) for: $q\"}"
    return 0
  fi
  curl -s -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "{\"question\":\"$q\"}"
}
