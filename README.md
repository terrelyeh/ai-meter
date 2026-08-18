# AI Meter

> **你是 AI agent 嗎？安裝流程請讀 [AGENTS.md](AGENTS.md)。**
> 本檔講的是設計理由與踩過的坑，不是安裝步驟。

macOS 選單列上的 AI 用量儀表。一眼看完 Claude Code、Codex、OpenRouter、Higgsfield 的剩餘額度。

```
make install     # 編譯 → 組 .app → 裝到 ~/Applications → 啟動
make probe       # 不開 UI，直接印出啟用中的來源現在的數字（除錯用）
make uninstall   # 移除 app 與開機啟動設定
```

## 開關與設定

面板底部只有一列：`↻ 重新整理` ／ `⚙︎ 設定` ／ `⏻ 結束`。設定都在齒輪選單裡：

- **顯示項目**：逐一開關四個來源。
- **選單列顯示**：選單列上要顯示哪一源。
- **選單列樣式**：徽章 + 數字（約 60pt）／只顯示數字（約 35pt）／只顯示徽章（約 20pt）。
- **更新頻率**：省電 / 標準 / 積極。
- **桌面面板**：在桌布上放一塊同樣的卡片。
- **開機啟動**：登入時自動啟動。

選單裡三組多選一都用 `.pickerStyle(.inline)` 攤平，不做巢狀子選單——
子選單要「點開齒輪 → 把滑鼠移過去 → 等它展開」，多一步而且要停住等 hover。
攤平之後選單變長（約 17 列），但一眼看完、一次點到，還能直接看到目前選的是哪個。

其他：

- **關掉**：面板右下角的電源鈕，或 `pkill -x AIMeter`。
- **再打開**：Spotlight 搜「AI Meter」，或 `open ~/Applications/"AI Meter.app"`。
- ⚠️ 勾了開機啟動又手動結束，**下次登入還是會啟動**。要永久不啟動就先取消勾選再結束。

### 顯示項目是真的停用

關掉一個來源不只是不顯示——**輪詢迴圈會整個被拆掉**，那個來源不會再發任何請求，
也不會再 fork 任何程序。`make probe` 也會跳過它並印「已停用，略過」，
這樣 probe 回報的才是 app 實際在做的事。

開關做成選單而不是四個常駐的勾選框，是因為**關掉的來源必須留在那份清單裡**。
否則關掉之後就從畫面上徹底消失，只能去改 `config.json` 才找得回來。
全部關掉時面板會直接說明去哪開回來。

停用狀態寫在 `~/.config/ai-meter/config.json`，跟首次啟動的自動偵測結果同一個地方——
沒裝的來源本來就會是關的，手動關掉只是同一個機制的另一個入口。

### 為什麼設定不獨立成一頁

曾經拆成獨立視窗，後來收回面板：這支是 `LSUIElement`，沒有主選單列，
⌘, 沒有東西可以掛，那個視窗得先 `NSApp.activate` 再 `openWindow` 才叫得出來
（不 activate 會開在別的 app 後面，看起來像沒反應）。
為幾個控制項付這個代價、還多一次點擊，不划算。

後來又從「常駐在面板底部」收進齒輪選單：五個控制項攤開時，設定區的視覺份量
幾乎跟上面四張資料卡一樣重，但這些設定幾乎不會動。選單就地彈出，
沒有視窗、不用 activate、不多一個 scene——跟那個被拿掉的設定視窗是兩回事。

## 桌面面板

齒輪選單裡勾「桌面面板」，會在桌布上放一塊同樣的卡片。可以整塊拖曳，位置會記住。

**這不是 WidgetKit 的 widget，是刻意的。** 真正的 widget 必須是 app extension，
而 macOS 的 extension 強制沙盒——沙盒一開，四個資料源死三個：讀不到 Claude 的資料檔、
不能執行 codex 與 higgsfield 的 binary。要把資料從主程式餵進去就得靠 App Group，
而 App Group 的識別碼在 macOS 上必須以 Team ID 開頭，那需要開發者帳號。
勉強做出來的 widget 只會有 OpenRouter 一張卡，金鑰還得編譯時寫死。

換成自己的 `NSWindow` 之後這些限制一個都不存在，四個來源的程式碼一行都不用改。
代價是它不會出現在系統的 widget 資源庫裡。

實作上有三個非做不可的細節：

- **層級用 `.normal - 1`，不能用 `.desktopIconWindow`。** 後者正是 Finder 桌面圖示視窗
  所在的層，排在它後面就等於被一片全螢幕的視窗蓋住，**看得到卻點不到**。
- **覆寫 `canBecomeKey` 為 true。** 無邊框 `NSWindow` 預設不能成為 key window，
  症狀是「剛開時拖得動，焦點一離開就再也點不到」。
- **還原位置要做邊界檢查。** 換螢幕或改解析度後舊座標可能落在畫面外，
  那會變成一個開著但看不見的視窗，比沒開更難查。

卡片跟選單列面板共用同一份 `SourceCard`，只差一個 `emphasis` 參數：桌面版底下是桌布，
淡色調完全看不見，所以底色改用系統的表面色、並靠邊框與陰影撐出分隔。

---

## 為什麼是選單列而不是控制中心

macOS 26 Tahoe 確實開放了第三方控制中心 control，但那必須是 WidgetKit extension；
extension 跑在沙盒裡，要跟主程式共用資料得靠 App Group entitlement，而那需要 Apple 簽章身分。
這台機器沒有開發者憑證，也不打算辦。

選單列 App 沒有這個限制：純 app、沒有 extension、ad-hoc 簽章（`codesign -s -`）本機就能跑。
如果哪天有了開發者帳號，`Providers/` 底下的東西可以原封不動被 widget extension 重用。

## 四個資料源

| 來源 | 取得方式 | 背景節奏 | 單次成本（實測） |
|---|---|---|---|
| Claude Code | `~/Library/Application Support/Claude/plan-usage-history.json` + `~/.claude/rate-limits.json` | 60s | 趨近於零 |
| Codex | `ChatGPT.app` 內附的 `codex app-server`，JSON-RPC | 15 min | 0.12s CPU、68 MB RSS |
| OpenRouter | `/credits` + `/analytics/query` + `/keys`，每個帳號一輪 | 15 min | 每帳號 3 個 HTTPS 請求 |
| Higgsfield | `higgsfield account status --json` | 30 min | 0.04s CPU、42 MB RSS |

## 耗電

穩態實測 **0.056% CPU**（180 秒只用掉 0.10 秒），RSS 穩定在 ~73 MB 不成長。

但 CPU 從來不是這種常駐小工具的主要耗電來源，所以節奏是照下面三個原則設計的：

1. **螢幕或系統睡著時完全停止輪詢**（`NSWorkspace` 的 sleep/wake 通知）。
   沒有這個的話，闔上蓋子整晚它還是會定期把 Wi-Fi 無線電從深度睡眠叫醒，
   而那段時間根本沒有人在看選單列。醒來時每個迴圈會先跑一次，所以數字立刻是新的。
2. **背景節奏放鬆，打開面板才抓最新的。** 選單列上的數字只要大致對就夠用；
   真的要看細節時會點開面板，`panelDidOpen()` 這時才付成本（有節流，連續開關不會重抓）。
3. **貴的源跑得更慢。** Claude 是讀本機小檔（而且 mtime 沒變就不重新解析），所以 60 秒無妨；
   Codex 每次要起一支 219 MB 的 binary，Higgsfield 要 fork node，那些就拉到 15 / 30 分鐘。

---

### Claude Code

**百分比**來自 `plan-usage-history.json`：

```json
{ "version": 2, "samples": [ { "t": 1786958526101, "org": "…",
  "u": { "fh": 25, "sd": 33, "xu": 0 } } ] }
```

`fh` = 5 小時窗用量 %、`sd` = 7 天用量 %、`xu` = 超額 %（沒超額時通常整個欄位不存在）。

**重置時間**不在那個檔裡。`resets_at` 只存在於 Claude Code 餵給 statusline 的 payload，
而那份 payload 只在 session 執行時出現。所以裝了一層 wrapper：

```
~/.claude/settings.json  statusLine.command → bash ~/.claude/statusline-mirror.sh
                                                 ├─ 把 rate_limits 寫進 ~/.claude/rate-limits.json
                                                 └─ payload 原封不動轉交給 statusline-command.sh
```

做成 wrapper 而不是改 `statusline-command.sh`，是因為那支是第三方的 starter kit，
改了它下次更新就沒了。wrapper 本身刻意寫成「絕不擋路」——鏡射失敗也一定把 payload 交出去，
否則 statusline 會整條消失，而使用者只會覺得 Claude Code 壞了。

讀不到鏡射檔不是錯誤，只是少了倒數；百分比照常顯示。

#### 為什麼不算 token

`~/.claude/projects/**/*.jsonl` 有完整 token 紀錄，但那是 771 個檔、1.3 GB，
而且同一次回應會被寫成多行、每行都帶一份完整的 `usage`（實測重複約 3.2 倍），
天真加總會多算三倍。要正確就得做增量 tail 加上依 `message.id` 去重。

代價那麼高，換來的只是「花了多少美金」的推估——但訂閱制付的是固定月費，
真正需要知道的是**額度用掉幾成**，而那個直接讀得到。

⚠️ `plan-usage-history.json` 由 **Claude 桌面 App** 寫入，只在它執行時更新。
程式會用樣本自己的時間戳判斷，超過 15 分鐘就標示，不會把舊數字當現況。
它是 Claude.app 的內部格式，沒有相容性承諾。

---

### Codex

使用者跑的是 **ChatGPT 桌面 App**，不是 npm 的 `codex` CLI（那支的 vendored binary 是壞的，別用）。
App 內附一支能用的 Rust binary，講 JSON-RPC over stdio：

```
/Applications/ChatGPT.app/Contents/Resources/codex app-server
  → initialize          （必須等它回應）
  → initialized
  → account/rateLimits/read
```

⚠️ **握手順序不能省。** 三行一次灌進去伺服器不會回你要的東西——實測會收到三行輸出但裡面沒有結果。
必須等 `initialize` 的回應到了才送後面兩行。

它跟 App 共用 `~/.codex/auth.json`，所以 token 換發不用我們管。
這也是為什麼不直接拿 `auth.json` 裡的 JWT 去打 OpenAI 後端——那樣要自己處理過期與換發。

⚠️ **視窗長度不要寫死成「5 小時 / 每週」。** 不同方案不一樣：這個帳號（`prolite`）
只有一個 `windowDurationMins: 10080` 的窗，`secondary` 是 `null`，**根本沒有 5 小時窗**。
顯示名稱一律由 `windowDurationMins` 推導。

只呼叫唯讀方法。`account/rateLimitResetCredit/consume` 會花掉一張重置額度、
`account/logout` 會把人登出——那些絕對不能碰。

---

### OpenRouter

`/credits` 給帳號餘額，`/analytics/query` 給每把 key 的花費，`/keys` 給上限。
點帳號那一列可以展開明細（預設收起）。

兩個坑：

1. `/credits` 需要 **management key**，一般 inference key 會 403。
   金鑰位置與帳號清單都在 `~/.config/ai-meter/config.json` 的 `openRouter`——
   `envFile` 指向一個 `.env`（預設 `~/.config/ai-meter/openrouter.env`），
   `accounts` 逐一列出 `{label, envKey}`。要幾個帳號就列幾筆。
2. **OpenRouter 會用 HTTP 200 回傳錯誤**，body 裡放 `{"error": {...}}`。
   只看 status code 會把錯誤當成功。

3. **key 清單與花費要用 analytics，不能用 `/keys`。**
   `/keys` 只涵蓋 provisioning API 建的金鑰。實測某個帳號用 `/keys` 只回一把
   usage $0 的 "Default key"，三把真正在花錢的（都是從網頁後台建的）
   完全看不到；改用 `POST /analytics/query` + `dimensions: ["api_key_id"]` 才全都拿得到，
   而且加總剛好等於帳號的 `total_usage`。

   但 analytics **不回上限**，也**看不出金鑰現在還在不在**——刪掉的 key，
   它的歷史花費會一直留在查詢結果裡。所以兩邊都要用：

   - `/keys` 有回東西時以它為準（刪掉的 key 自然消失）
   - 回空的時候代表這個帳號的金鑰它全看不到，才退回 analytics 的清單

   兩種情況實測都遇過：一個帳號 `/keys` 回 4 把（剛刪掉的那把已不在），
   另一個帳號 `/keys` 回空、三把在花錢的全靠 analytics 才看得到。

   被濾掉的花費不會憑空消失，它落到最後那列「其他」（已刪除或後台建立的金鑰）。
   少了那一列，帳號明細會加總不到實際花掉的錢，而且不會有任何提示。

`time_range` 的參數名不能寫成 `start_date`/`end_date`，那樣不會報錯，會靜默回傳預設區間。

一個帳號失敗不影響另一個；明細拿不到也不會讓餘額跟著失敗。
兩個帳號在面板裡各自成塊（自己的底色＋左側色條），因為並排時光靠列距分不出哪些 key 屬於誰。

---

### Higgsfield

官方 API docs 只有送件 / 查狀態 / 取消，沒有餘額端點。但本機的 `@higgsfield/cli`
有 `account status --json`。

實測這支 CLI 大約每五次失敗一次，訊息是 `Error: request failed (no response received)`。
那是網路層抖動，**不是憑證過期**——所以會重試 3 次（間隔 2 秒），並把這類錯誤跟認證錯誤分開，
不會叫你去跑一個沒必要的 `higgsfield auth login`。

---

## 共通的錯誤處理原則

**失敗時保留上次的好數字並標明時間，不要清成空白。**
空白看起來像「沒事」，那比顯示一個標明過期的舊數字更危險。四個源都是這樣。

失敗的區塊留在原地講清楚發生什麼事，並給出可執行的下一步。
各源互不影響——Higgsfield 憑證過期不該讓 Claude 那一格消失。

## 除錯

```bash
make probe
```

走的是**跟 UI 完全同一份** provider 程式碼。它印出來的對，選單列裡的就對。

五個路徑都能用環境變數覆寫，用來測錯誤路徑而不必動到真的檔案：

```bash
AIMETER_CLAUDE_HISTORY=/tmp/bad.json \
AIMETER_RATE_LIMIT_MIRROR=/tmp/nope.json \
AIMETER_OPENROUTER_ENV=/tmp/bad.env \
AIMETER_CODEX_BIN=/nonexistent \
AIMETER_HIGGSFIELD_BIN=/nonexistent \
  ./.build/release/AIMeter --probe
```

## 結構

```
Sources/AIMeter/
  AIMeterApp.swift       @main，--setup / --probe 在這裡分流
  Setup.swift            環境偵測、建立設定檔、列出還缺什麼
  Probe.swift            CLI 驗證模式
  Config.swift           ~/.config/ai-meter/config.json 的讀寫與自動偵測
  SourceKind.swift       四個來源的識別；「對每個來源做一件事」都走它
  Refresher.swift        各源的更新迴圈、警戒門檻、選單列標題選誰
  UsageModel.swift       SourceBox / Metric（可巢狀）/ Brand / SourceStatus
  MenuBarSelection.swift 選單列顯示哪一源
  RefreshCadence.swift   省電 / 標準 / 積極 三檔的實際秒數
  LoginItem.swift        LaunchAgent 開機啟動
  Providers/             五個資料源 + .env 解析 + 測試用路徑覆寫
  UI/                    面板、桌面面板、可展開的列、進度條、選單列徽章
```

`SourceKind` 值得一提：在它之前，「對每個來源做一件事」都是一條四行的 if 串——
建輪詢迴圈、收集卡片、手動重整、面板開啟時重抓——每加一個地方就多抄一份，
而漏掉其中一個**不會有編譯錯誤**。現在那些都是一次 `for kind in SourceKind.allCases`。

沒有 `.xcodeproj` 是刻意的——`swift build` 在 CLI 就跑得動，`.app` 不過是
一個 Info.plist 加一支執行檔，`scripts/bundle.sh` 幾行就組完。

## 數字講剩餘，進度條講已用

兩者**刻意不同向**，各自解決一個問題。

**數字用剩餘。** 使用者的 Claude Code statusline 顯示的就是剩餘
（雷蒙那套 starter kit 算的是 `100 - used`）。兩邊講同一件事卻反過來的話，
每次對照都要心算。統一之後選單列的 63% 跟 statusline 的 63% 是同一個數字。

**進度條用已用。** 「條很短」直覺上像「還沒用多少」，要多想一秒才會意識到
那其實是快用完了。填滿才是逼近極限，那是通用的閱讀方式——
macOS 自己的儲存空間指示器正是這個組合：條隨已使用量填滿，文字寫「可用 86 GB」。

文字上的規則：**無標示 = 剩餘**，只有真的沒有「剩餘」可言的才標「已用」——
沒設上限的 key、超額、以及「其他」那一列。只標例外，雜訊最少。

`Metric.fraction` 的語意固定是已用比例，程式碼裡有註解說明它跟 `value` 是刻意不同向的；
不寫的話下一個人會當成 bug 修掉。

## 警戒門檻

一律看**剩餘**，低於門檻才亮。

| | 黃 | 紅 |
|---|---|---|
| Claude 5 小時窗 | 剩 ≤ 40% | 剩 ≤ 20% |
| Claude 7 天 | 剩 ≤ 30% | 剩 ≤ 10% |
| Codex 各視窗 | 剩 ≤ 30% | 剩 ≤ 10% |
| OpenRouter 帳號餘額 | < $15 | < $5 |
| OpenRouter 單把 key | 剩 ≤ 25% | 剩 ≤ 10% |
| Higgsfield credits | < 1500 | < 500 |

子項的警戒會往上冒泡，所以某把 key 快撞上限時，就算收起來也看得到。

## 選單列顯示哪一個

面板底部可以選，會記住（存在 `UserDefaults` 的 `menuBarSelection`）。

- **自動**（預設）：平常顯示 Claude；任一源進入警戒就換成那一個。
- **釘住某一源**：永遠顯示它。但如果**別的**源進入 critical，前面會多一個 `⚠︎` 圓點——
  釘住是為了讓你自己決定看什麼，不是為了把壞消息藏起來。

一個來源有多個指標時，選單列顯示哪一個由 `SourceBox.headlineMetricID` 指定。
Claude 指定 **7 天**而不是 5 小時窗：5 小時窗一直在重置、數字跳來跳去，
真正會卡住你一整週的是 7 天那條。沒被顯示到的指標如果進入 critical，
會讓選單列亮起 `⚠︎` 記號，但**不會**把你指定要看的數字換掉。

### 選單列塞不下的時候

選單列的空間是固定的，圖示一多，排在後面的項目會**直接不被畫出來**——
app 還在跑，只是看不到（實測：接上外接螢幕後就出現了）。所以寬度做成可調的，
在齒輪選單的「選單列樣式」裡選。另外按住 ⌘ 拖曳可以重排選單列圖示，
把它移到靠近時鐘那側就不會是第一個被擠掉的。

選單列上不靠顏色分辨（系統的 template rendering 會吃掉），所以四個符號的輪廓刻意差很多：
星芒 / 角括號 / 分岔 / 底片。面板裡才用彩色徽章，那裡顏色是最快的掃描線索。

## 介面上的兩個刻意決定

**每個來源一張卡，不用分隔線。** 分隔線只是一條細線，底色是一整塊面積，區隔感差很多。
卡片外框在該來源進入警戒時會加深，所以不用讀數字也知道哪一塊要注意。

**時間戳帶到秒，而且更新中會轉圈。** 各源的數字常常前後一模一樣，
如果時間戳只到分鐘，同一分鐘內按「重新整理」畫面完全不會動——
按鈕其實有作用，但看起來像壞掉。這是回饋問題，不是功能問題。
