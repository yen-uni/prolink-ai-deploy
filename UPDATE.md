# ProLink AI 升級指引

簽約客戶定期升級到最新 release 版本。本文件對應 Cloud Shell 升級 tutorial。

## 步驟 1 — 開啟 Cloud Shell

如果你是從 [prolink.tw/deploy](https://prolink.tw/deploy) 點「檢查更新」按鈕進來、Cloud Shell 已經自動 clone 本 repo。

如果你 SSH 進客戶 VM 手動升級:

```bash
cd ~/prolink-ai-deploy
git pull
```

## 步驟 2 — 執行升級精靈

```bash
bash wizard/customer_update_wizard.sh
```

精靈會自動跑 4 步:

1. **偵測本機 backend image** — `docker inspect uni-ai-backend`
2. **查 Registry 最新 release** — `gcloud artifacts docker tags list`
3. **升級確認** — whiptail 對話框顯示 `cur → latest`、確認後繼續
4. **升級執行** — `docker compose pull` → `up -d` → backend healthcheck

## 步驟 3 — 升級後驗收

進 WP admin、跑一次客戶實際用 case 的 dogfood、確認:

- 對話功能正常(LINE / Web chat)
- 知識庫查詢回答仍對
- 行政後台 dashboard 載入正常

## 常見錯誤處理

**Q: docker pull 回 401 / 403 / Unauthorized**
A: 表示 GCP 授權失效。可能原因:
- 月費未繳、ProLink AI 已撤銷 IAM binding
- 客戶 GCP SA 設定變動、需重新授權
- 解法:聯繫 LINE ID: 0919yen 處理

**Q: 已是最新版**
A: 精靈會直接 print「已是最新版本」並結束、沒有 side effect。

**Q: 升級後 backend 起不來**
A: 看 `docker compose logs backend` 找錯誤、必要時 `git revert` rollback 到上個 image tag、聯繫 ProLink。

**Q: 想 dry-run 不真的升級**
A: 設 `TEST_MODE=1 bash wizard/customer_update_wizard.sh`、所有外呼走 dummy、看流程不真實 pull。

## 升級頻率建議

| 月費方案 | 建議升級頻率 |
|---|---|
| 基礎 | 每季一次(release-vX.0 主版本出來時) |
| Pro | 每月一次(看 CHANGELOG 有 critical fix 立即升) |
| Enterprise | 客製 |

詳見 [CHANGELOG.md](CHANGELOG.md) 看每個 release 含哪些改動。
