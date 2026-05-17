# 客戶授權操作 SOP

> 內部文件 — ProLink AI 商業化授權管理。
> 簽約客戶月費綁 GCP Artifact Registry `roles/artifactregistry.reader` IAM binding。

---

## 模型

- 客戶簽約 → 發 GCP service account → 加 reader binding
- 客戶 docker pull 走自己 SA → IAM check → 通過拉 image / 升級
- 客戶停繳月費 → 撤銷 binding → docker pull 回 401/403 → update wizard 自動顯示「請聯繫」msgbox
- 既有 image 已在客戶 VM 本機 → 撤銷不影響運行、只影響後續升級

---

## 給新客戶授權(簽約啟用)

客戶簽約後、ProLink AI 拿到客戶 GCP project ID + service account email,執行:

```bash
gcloud artifacts repositories add-iam-policy-binding uni-ai-backend \
  --location=asia-east1 \
  --member="serviceAccount:<CUSTOMER_SA>@<CUSTOMER_PROJECT>.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader" \
  --project=ecstatic-emblem-490504-d5
```

替換:
- `<CUSTOMER_SA>` — 客戶提供的 SA 名稱
- `<CUSTOMER_PROJECT>` — 客戶 GCP project ID

驗收:
```bash
gcloud artifacts repositories get-iam-policy uni-ai-backend \
  --location=asia-east1 \
  --project=ecstatic-emblem-490504-d5 \
  --format="value(bindings[].members)" | grep "<CUSTOMER_SA>"
```
應該看到客戶 SA email。

---

## 撤銷客戶授權(停止續約)

客戶月費未繳超過寬限期、執行:

```bash
gcloud artifacts repositories remove-iam-policy-binding uni-ai-backend \
  --location=asia-east1 \
  --member="serviceAccount:<CUSTOMER_SA>@<CUSTOMER_PROJECT>.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader" \
  --project=ecstatic-emblem-490504-d5
```

驗收:同上 `get-iam-policy`、客戶 SA 應該消失。

---

## 客戶端表現

| 狀態 | docker pull 結果 | wizard 表現 | 既有部署 |
|---|---|---|---|
| 授權有效 | 成功 | 升級正常 | 用最新 image |
| 授權撤銷 | 401/403 | whiptail msgbox「請聯繫」 | 沿用既有 image、不停機 |
| 從未授權 | 401/403 | 同上 | 部署精靈無法 pull image |

關鍵: **撤銷授權不下線客戶服務**、只切斷升級路徑。客戶仍可用既有版本運行、避免月費爭議升級成服務中斷糾紛。

---

## 觀察客戶 pull 行為

GCP Audit Log 可看客戶 SA 何時 docker pull:

```bash
gcloud logging read \
  'resource.type="audited_resource" AND
   protoPayload.serviceName="artifactregistry.googleapis.com" AND
   protoPayload.methodName=~"DockerRead"' \
  --project=ecstatic-emblem-490504-d5 \
  --limit=50 \
  --format="value(timestamp, protoPayload.authenticationInfo.principalEmail)"
```

可判斷客戶是否真的在升級、續約議題交涉時的事實依據。

---

## 客戶月費對應方案表

| 方案 | image 升級 | LINE 訂閱 | 工時上限 |
|---|---|---|---|
| Free trial 7 天 | 不升 | ProLink LINE 訊息 limit | 無 |
| 基礎月費 | 季升 | 客戶自己 LINE channel | 1 hr/月 hotline |
| Pro 月費 | 月升 | 同上 | 4 hr/月 hotline |
| Enterprise | 客製 | 同上 | SLA 簽 |

(本表為內部參考、實際合約以 SoW 為準。)
