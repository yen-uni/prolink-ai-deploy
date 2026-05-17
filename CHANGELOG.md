# CHANGELOG

本檔記錄 ProLink AI 部署精靈 + 客戶 image 的每次 release。

升級用 `bash wizard/customer_update_wizard.sh`(會自動拉 Registry 最新 release tag、docker compose pull + up -d + healthcheck)。

---

## release-v1.0 (2026-05-18)

第一個商業化 release 版本。對外給簽約客戶。

### 商業化基礎
- 品牌動態載入(brand_zh / brand_en / company_phone)、site brand swap 24 處對齊客戶名
- Schema Tier A 17 個 critical field + drift fix
- Sheets ingest 動態載入、隱藏 tab 自動排除
- Multi-tenant tenant_helpers(DB / sheet / acl 全 routing 接 tenant context)

### Security hardening
- 4 處 fail-closed(admin_config / admin_line / deps / main 入口)
- Python deps CVE 升級(langchain / transformers / pip)
- NAS + contacts/search 補 auth
- LLM prompt + tool docstring PII 名稱 → placeholder

### Dead code cleanup
- HybridIntentClassifier / RerankerType.LLM mode 共 -942 LOC
- Zero-ref services + orphan dir + replaced + misplaced tests 清理

### 部署精靈
- 17 步驟 deploy wizard + whiptail TUI(Debian-installer 風)
- 4 步驟 update wizard(本 release 新增)
- 中斷續跑、自動斷點偵測

### 升級流程(從更早版本)
本 release 是第一個對外版本、無 prior tag。新部署直接走 `bash wizard/customer_deploy_wizard.sh`。

---

## 版本標記原則

- `release-vMAJOR.MINOR` — semver-ish
- MAJOR bump = breaking change(client IT 須重看 deploy SOP)
- MINOR bump = feature add / hotfix
- 客戶 image 推到 GCP Artifact Registry:
  `asia-east1-docker.pkg.dev/ecstatic-emblem-490504-d5/uni-ai-backend/uni-ai-backend:release-vX.Y`
- 同時推 `release-latest` 滑動 tag、wizard 預設拉這個

---

## 授權

升級需要客戶 GCP service account 對 Artifact Registry 有 `roles/artifactregistry.reader` 權限。撤銷授權後 `docker pull` 回 401/403、wizard 自動顯示「請聯繫 ProLink AI 續約」訊息;既有部署不受影響、可繼續使用既有 image。

詳見 [docs/LICENSE_OPERATION.md](docs/LICENSE_OPERATION.md)。
