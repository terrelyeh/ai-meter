# AI Meter — 安裝 runbook

macOS 選單列工具，顯示 Claude Code / Codex / OpenRouter / Higgsfield 的剩餘額度。
本檔是**給 agent 執行的安裝流程**。

- 設計理由與各 API 踩過的坑 → [README.md](README.md)
- 要**修改這支程式**而不是安裝它 → [CLAUDE.md](CLAUDE.md)

使用者只要裝他自己有在用的服務。沒偵測到的來源會自動停用，不會留下錯誤訊息。

## 前置

```bash
swift --version    # 沒有就請使用者跑 xcode-select --install
jq --version       # 沒有就 brew install jq
sw_vers -productVersion   # 需要 14 以上
```

三項齊全才往下走。

## 安裝

依序執行。**每一步的驗證通過才進下一步**——前一步沒過就往下做，最後只會得到一個看起來裝好、實際上沒資料的工具。

### 1. `make setup`

偵測環境、建立 `~/.config/ai-meter/config.json`。冪等，既有設定檔絕不覆寫。

- **exit 0** → 進第 2 步。
- **exit 1** → 它會印出「還需要人類提供」清單，每一項都附了為什麼與拿到之後要做什麼。
  照著問使用者（見下方〈要問使用者的兩件事〉），處理完**重跑 `make setup` 直到 exit 0**。

完成條件：`make setup` exit 0。

### 2. `make install`

編譯、組 `.app`、裝到 `~/Applications`、啟動。

完成條件：`pgrep -f "AI Meter"` 有輸出。

### 3. `make probe`

用與 UI 完全相同的 provider 程式碼把每個啟用的來源跑一次。

完成條件：**每個啟用的來源都是 `✓`**。出現 `✗` 就查〈失敗對照〉，修好再跑一次。

### 4. 請使用者確認畫面

請他看選單列右上角，並點開面板。這一步無法由 agent 驗證。

## 要問使用者的兩件事

只有這兩件事需要人類決定。其餘全部自動。

**其一，OpenRouter 金鑰**（僅當他要用 OpenRouter）：

> 你的 OpenRouter management key 是什麼？每個帳號一把。
> 注意是 management key，不是一般的 inference key——後者查餘額會回 403。

拿到後寫進設定檔指定的 `envFile`（預設 `~/.config/ai-meter/openrouter.env`），
格式 `OPENROUTER_MGMT_A=sk-or-v1-…`，然後 `chmod 600`。
多個帳號就在 `config.json` 的 `openRouter.accounts` 各加一筆 `{label, envKey}`。

**其二，Claude 重置倒數**（僅當他要用 Claude Code）：

> 要不要顯示 Claude 額度的重置倒數？這需要在你的 `~/.claude/settings.json` 的
> statusline 前面插一層 wrapper。不裝也能用，只是少了倒數，百分比照常顯示。

他同意才跑 `make setup-statusline`。反悔用 `make unsetup-statusline`。

## 失敗對照

| probe 顯示 | 意思 | 做什麼 |
|---|---|---|
| 找不到 plan-usage-history.json | Claude 桌面 App 沒開過 | 請使用者開一次 Claude.app |
| 讀不到鏡射檔 | statusline wrapper 還沒裝，或裝了但還沒有 session 跑過 | 跑 `make setup-statusline`，然後請使用者開一個新的 Claude Code session |
| `User not found.` | OpenRouter 金鑰錯誤或不是 management key | 跟使用者確認金鑰種類 |
| 找不到 higgsfield CLI | 沒裝 | `npm i -g @higgsfield/cli`，或在面板的「顯示項目」把它關掉 |
| Higgsfield 服務暫時無回應 | 上游抖動，非認證問題 | 已自動重試 3 次。稍後再跑一次 probe |
| codex app-server 沒有回應 | ChatGPT App 未登入 | 請使用者開 ChatGPT App 確認登入狀態 |
| 找不到 ChatGPT.app 裡的 codex | 沒裝 ChatGPT 桌面 App | 在面板的「顯示項目」把它關掉 |

## 守則

**在本機編譯，不要提供或下載編譯好的 `.app`。** 本專案是 ad-hoc 簽章，沒有經過 Apple 公證；
從網路下載的 `.app` 會被標記 quarantine，macOS 15 之後使用者得手動去系統設定放行。
本機 `swift build` 出來的沒有這個屬性，直接就能跑。

**改 `~/.claude/settings.json` 一律走 `make setup-statusline`。** 那支腳本會先備份、
產生 wrapper 後拿同一份 payload 比對新舊輸出、完全一致才套用，不一致自動回滾。
手動編輯繞過這些保護，改壞了使用者的 statusline 會整條消失，而他只會覺得 Claude Code 壞了。

**要調整行為就改 `~/.config/ai-meter/config.json`。** 金鑰位置、帳號清單、
各來源開關都在裡面，不需要動 source code。

**驗證一律用 `make probe`。** 它跟 UI 走同一份程式碼，它說對的就是對的。
