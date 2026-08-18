# CLAUDE.md — 開發備忘錄

> Last updated: 2026-08-18

這份是給**接手改程式碼**的 AI 看的。另外兩份文件職責不同，不要混：

| 文件 | 讀者 | 回答 |
|---|---|---|
| **CLAUDE.md**（本檔） | 改這支程式的 AI | 怎麼改、哪裡有雷、下一步是什麼 |
| [AGENTS.md](AGENTS.md) | 幫別人安裝的 AI | 照著裝的步驟與驗證 |
| [README.md](README.md) | 人 | 這是什麼、為什麼這樣設計、每個 API 的坑 |

**README 不尋常地詳細**——四個資料源各自的 API 陷阱、為什麼不做 widget、
為什麼不做控制中心，全都寫在裡面了。這裡不重複，只寫 README 沒有、但下一個
session 一定會用到的東西。

## Project Overview

macOS 選單列工具，顯示 Claude Code / Codex / OpenRouter / Higgsfield 的剩餘額度。
純本機、單一使用者、無後端。功能全貌見 [README.md](README.md)。

## Tech Stack

- **Swift 6**（`swiftLanguageMode(.v5)`）+ SwiftUI，macOS 14+
- **SwiftPM，沒有 `.xcodeproj`**。`.app` 由 `scripts/bundle.sh` 手工組，ad-hoc 簽章
- 零第三方依賴

## Directory Structure

```
Sources/AIMeter/
  AIMeterApp.swift       @main；--setup / --probe 在這裡分流
  Setup.swift            環境偵測、建設定檔、列出還缺什麼（非互動）
  Probe.swift            CLI 驗證模式
  Config.swift           ~/.config/ai-meter/config.json
  SourceKind.swift       四個來源的識別 + 每源的間隔／門檻對照
  Refresher.swift        更新迴圈、指標建構、警戒判斷、選單列標題選誰
  UsageModel.swift       SourceBox / Metric / Brand / SourceStatus
  Providers/             五個資料源 + .env 解析 + 測試用路徑覆寫
  UI/                    選單列徽章、面板、桌面面板、卡片、進度條
scripts/setup-statusline.sh   在使用者的 statusline 前插一層 wrapper
```

## Architecture

單向：`Providers/*`（純函式、不碰 UI）→ `Refresher`（@MainActor @Observable，
把原始資料轉成 `Metric`）→ `SourceBox`（每源一個狀態容器）→ UI 讀 `boxes`。

**`SourceKind` 是擴充點。** 「對每個來源做一件事」（建迴圈、收集卡片、手動重整、
面板開啟時重抓、probe）全都走 `for kind in SourceKind.allCases`。加新來源時
只改 `SourceKind` 與 `Refresher`，不要在各處複製 if 串——那正是它存在的理由。

選單列面板與桌面面板**共用同一個 `SourceCard`**，只差一個 `emphasis` 參數。

## Conventions

這幾條是刻意的設計，看起來像 bug 但不是：

1. **`Metric.value` 講剩餘，`Metric.fraction` 講已用。** 兩者不同向。
   數字用剩餘是為了跟使用者的 Claude Code statusline 一致（那支腳本算 `100 - used`）；
   條用已用是因為「短條」直覺上像「還沒用多少」。
2. **文字上：無標示 = 剩餘。** 只有真的沒有剩餘可言的才標「已用」
   （沒設上限的 key、超額、「其他」那列）。只標例外。
3. **失敗時保留上次的好數字**（`.degraded`），不要清空。空白看起來像「沒事」。
4. **停用的來源是不存在，不是灰掉。** 連輪詢迴圈都不建。

## 錯誤分類 — 接新資料源前先讀這段

這輪踩了**三次**同一個坑：Higgsfield 每五次抖一次、Higgsfield 找不到 node、
Codex 帳號狀態還沒載好。三次都被歸類成「憑證過期，請重新登入」——
**而那個訊息比錯誤本身更有害**，使用者會去重登一個根本沒壞的帳號。

所以接新來源時，**先把錯誤分成三類再寫 UI**：

| 類別 | 特徵 | 該給的提示 |
|---|---|---|
| 暫時性 | 自己會好（網路抖動、服務還沒 ready） | **不給提示**，重試就好 |
| 環境問題 | 缺 runtime、CLI 沒裝、PATH 不對 | 指向要裝什麼／改什麼 |
| 認證問題 | 真的需要人重新登入 | 才給 auth 指令 |

`HiggsfieldSource.Failure` 與 `CodexSource.Failure` 是現成的範本，兩者都有
`isTransient`，重試邏輯掛在上面。

## 驗證方式（有一個陷阱）

```bash
make probe      # 用與 UI 完全同一份 provider 程式碼跑一次
make install    # 編譯 → 組 .app → 裝到 ~/Applications → 啟動
```

⚠️ **`make probe` 過了不代表 app 沒事。** probe 從終端機執行，繼承你 shell 的
`PATH`；app 由 Finder／LaunchAgent 啟動時 `PATH` 只有系統最小預設值。
node 那個 bug 就是這樣漏掉的。改動任何**會 fork 子程序**的東西之後，一定要跑：

```bash
env -i HOME="$HOME" PATH=/usr/bin:/bin ./.build/release/AIMeter --probe
```

錯誤路徑用環境變數覆寫來測，不必動真的檔案（五個路徑都可覆寫，見 README）：

```bash
AIMETER_HIGGSFIELD_BIN=/tmp/fake ./.build/release/AIMeter --probe
```

測分類邏輯最快的方法是寫一支假 CLI 印出特定 stderr 再 `exit 1`。

## 已經查過、結論是不做

**別重查這兩件事**，都花了不少時間：

- **Vercel**（2026-08-18）：使用者要的是「Pro 包含額度用掉幾成」，而**公開 API
  沒有任何端點給得出分母**（計費相關端點只有 10 條，其餘都是 Marketplace 整合商用的）。
  另外 `vercel usage` 這個 CLI 指令是壞的（單日區間伺服器有回資料，但 CLI 用
  `.json()` 解 NDJSON 會爆），而 `/v1/billing/charges` **只吃單日區間**，
  2 天以上一律 500。若哪天 Vercel 補上額度端點，可以再評估。
- **WidgetKit widget**：extension 強制沙盒 → 讀不到 Claude 資料檔、不能執行 codex
  與 higgsfield 的 binary → 要靠 App Group 餵資料 → App Group 需要 Team ID →
  需要開發者帳號（使用者明確不辦）。改用自己的 `NSWindow`（`UI/DesktopPanel.swift`），
  細節與三個必踩的坑見 README。

## Next Steps

- **找同事實測安裝**：讓對方的 AI 讀 `AGENTS.md` 自己裝一次。那是唯一能驗證
  runbook 夠不夠用的方法，目前還沒有人跑過。
- **卡片排序**（使用者問過，暫時擱置）：讓面板裡四張卡可以重排。
- **多帳號**（使用者問過，決定等真的有第二個帳號再做）：OpenRouter 本來就多帳號；
  Claude 可靠 `plan-usage-history.json` 的 `org` 欄位分列（目前只有一個 org，
  沒有真實資料可驗證）；Codex 難做，`~/.codex/auth.json` 只存一組登入。
- **git 歷史含內部命名**：前七個 commit 的原始碼註解裡有三個 EnGenius 內部 key
  名稱。使用者已決定不改寫歷史，知道就好。

## OpenRouter analytics 的查詢窗上限（實測 2026-08-18）

上限**依維度而定**，不是一個固定值：

| 維度 | 上限 | 超過時的錯誤 |
|---|---|---|
| `api_key_id`（各金鑰用量） | **367 天** | `time_range exceeds maximum of 367 days` |
| `external_user`（功能標籤） | **31 天** | `exceeds maximum of 31 days for the requested metrics/dimensions` |

常見的誤解是「analytics 只有 31 天」——那個限制只套在 `external_user` 上。
本專案查的是 `api_key_id`，所以拿得到一整年。

`fetchUsageByKey` 用 **365 天**，刻意留一點餘裕不去貼 367 的上限。

⚠️ **帳號用超過一年之後會出現一個沉默的偏差**：更早的花費落在查詢窗外，
各 key 的加總會少於帳號的終身 `total_usage`，差額自動掉進「其他」那一列。
金額仍然加得起來（所以不會誤導），但那列的文案「已刪除或後台建立的金鑰」
屆時就不完全準確了。真的發生時改文案即可。

目前這個帳號終身總花費 $31.83、365 天窗合計 $31.84——幾乎完全吻合，還沒到那一天。

## Common Pitfalls

- **改 `~/.claude/settings.json` 一律走 `scripts/setup-statusline.sh`。**
  它會備份、比對新舊輸出一致才套用、不一致自動回滾。手動改壞了使用者的
  statusline 會整條消失，而他只會覺得 Claude Code 壞了。
- **bash 裡 `$VAR` 後面直接接全形字**（`$WRAPPER（`）會被當成變數名的一部分，
  `set -u` 下直接 unbound variable。全部寫成 `${VAR}`。
- **`timeout` 指令在 macOS 上不存在。** 用背景程序加 `kill`，否則整條指令會
  靜默失敗而你以為它跑過了。
- **選單列吃不到顏色**（template rendering）。徽章是用 `ImageRenderer` 畫成
  `isTemplate = false` 的 NSImage 才有底色；四個符號的**輪廓**也要夠不一樣。
- **選單列塞不下時項目直接不畫出來**，app 還在跑但看不到。已提供「選單列樣式」
  讓使用者縮窄；診斷時先確認是不是空間問題再查程式。
- **桌面面板**：層級不能用 `.desktopIconWindow`（會被 Finder 那片全螢幕桌面視窗
  蓋住，看得到點不到），且必須覆寫 `canBecomeKey`（無邊框視窗預設不能成為
  key window，症狀是焦點一離開就拖不動）。
