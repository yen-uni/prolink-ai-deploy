# ProLink AI 部署精靈

ProLink AI 客戶端一鍵部署工具。17 步驟、預估 25 分鐘、跨 Windows / Mac / Linux,**無需安裝任何軟體**。

## 一鍵部署(推薦)

點下方按鈕,瀏覽器自動開啟 Google Cloud Shell 並載入精靈:

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.png)](https://shell.cloud.google.com/cloudshell/open?cloudshell_git_repo=https://github.com/yen-uni/prolink-ai-deploy&cloudshell_tutorial=TUTORIAL.md)

開啟後請依右側 tutorial 步驟操作。

## 手動執行

如需在自有 VM 上跑(已 SSH 進客戶 GCP VM):

```bash
git clone https://github.com/yen-uni/prolink-ai-deploy
cd prolink-ai-deploy
bash wizard/customer_deploy_wizard.sh
```

## 系統需求

- Debian / Ubuntu(`whiptail` 預裝;若無、精靈會詢問是否 `sudo apt-get install`)
- bash 4+
- `jq`、`openssl`、`docker`、`gcloud` CLI
- GCP project + n2-standard-2 以上 VM

## 部署流程

精靈會帶你完成:

1. GCP 專案 / VM 機型確認
2. 品牌名稱(中英文)
3. DB 連線、API key(OpenAI / Anthropic)
4. HMAC secret 生成、Logo 上傳
5. Docker compose pull + up
6. Healthcheck(backend / WordPress / DB)
7. Let's Encrypt SSL + LINE webhook 接通
8. 知識庫匯入(PDF)、WP admin 帳號建立
9. 產 handoff 文件 + 第一次 dogfood

中斷可重跑、自動從斷點續(`/home/yen/.wizard_state.json`)。

## 測試模式

```bash
TEST_MODE=1 bash wizard/customer_deploy_wizard.sh
```

所有外呼(gcloud / API / docker / mysql / certbot / LINE)走 dummy,17/17 全綠 = 框架正常。

## 授權

Copyright © 2026 ProLink AI. 詳見 [LICENSE](LICENSE)。
