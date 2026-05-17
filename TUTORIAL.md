# 歡迎使用 ProLink AI 部署精靈

預估 25 分鐘、17 步驟。本 tutorial 會引導你完成第一次部署。

## 步驟 1 — 確認環境

精靈會跑在 Google Cloud Shell 上(已內建 `bash`、`gcloud`、`jq`)。

請先確認:

- 已準備好客戶的 GCP **project ID**
- 已開好 VM(建議 n2-standard-2 以上、Debian 12 或 Ubuntu 22.04)
- 已準備好 OpenAI API key(`sk-...`)
- 已準備好 LINE Channel access token / secret(如需 LINE 整合)
- 已準備好客戶 domain(用於 SSL)

## 步驟 2 — 開始部署

執行:

```bash
bash wizard/customer_deploy_wizard.sh
```

精靈會跳出 Debian-installer 風格的對話框、一步步引導輸入。

## 步驟 3 — 中斷與續跑

- 隨時按 `Ctrl+C` 可中斷,進度自動存於 `~/.wizard_state.json`
- 再跑一次 `bash wizard/customer_deploy_wizard.sh` 自動從斷點續
- 輸入 `B` 可回上一步

## 步驟 4 — 完工後

精靈跑完會產:

- `~/CUSTOMER_HANDOFF_<brand>_<date>.md` — 給客戶 IT 的 handoff 文件
- WP admin 帳號 / 密碼(對話框顯示一次,**請立即存入密碼管理員**)

## 升級現有部署

簽約後 ProLink AI 會定期推 release-v*.* 新版到 GCP Artifact Registry。已部署的客戶執行下列指令一鍵升級:

```bash
cd ~/prolink-ai-deploy
bash wizard/customer_update_wizard.sh
```

升級流程(4 步):

1. 偵測本機 backend image tag
2. 查 Registry 最新 release tag
3. 比對版本、whiptail 顯示確認對話框
4. `docker compose pull` → `up -d` → healthcheck

升級失敗(`docker pull` 回 401/403)= 月費停繳、授權失效。精靈會自動顯示「請聯繫 LINE ID: 0919yen」訊息;既有部署 image 仍在本機、不受影響、可繼續使用。

詳見 [UPDATE.md](UPDATE.md) 與 [CHANGELOG.md](CHANGELOG.md)。

## 常見問題

**Q: 跑到一半失敗怎麼辦?**
A: 看 `~/wizard_run_<date>.log`,精靈會印失敗原因與建議下一步。修正後重跑會自動續。

**Q: 想先試流程不真實部署?**
A: 設 `TEST_MODE=1` 環境變數、所有外呼走 dummy。

**Q: whiptail 跳不出來?**
A: 精靈會自動 fallback 純文字 prompt、不影響功能。如需 TUI:`sudo apt-get install whiptail`。

**Q: 升級時 docker pull 報「unauthorized」怎麼辦?**
A: 表示 GCP 授權失效(月費停繳或客戶 SA 設定問題)。請聯繫 LINE ID: 0919yen 處理。

---

完成所有步驟後、請聯絡 ProLink AI 技術支援完成正式驗收。
