APP_NAME := AI Meter
BUNDLE_ID := com.terrelyeh.aimeter
INSTALL_DIR := $(HOME)/Applications
PLIST := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist

.PHONY: build bundle setup setup-statusline unsetup-statusline probe run install uninstall clean

build:
	swift build -c release

bundle: build
	@bash scripts/bundle.sh

## 偵測環境、建立設定檔、列出還缺什麼。非互動、可重跑、不覆寫既有設定。
setup: build
	@"$$(swift build -c release --show-bin-path)/AIMeter" --setup

## 接上 Claude 額度的重置倒數。會改 ~/.claude/settings.json（先備份、比對輸出、不一致自動回滾）
setup-statusline:
	@bash scripts/setup-statusline.sh

## 還原 statusline 設定
unsetup-statusline:
	@bash scripts/setup-statusline.sh --uninstall

## 不開 UI，用同一份 provider 程式碼把每個啟用的來源跑一次印出來
probe: build
	@"$$(swift build -c release --show-bin-path)/AIMeter" --probe

## 重跑一份新的：先關掉舊的，避免選單列上出現兩個圖示
run: bundle
	@pkill -x AIMeter 2>/dev/null || true
	@open "build/$(APP_NAME).app"
	@echo "跑起來了，看選單列右上角"

install: bundle
	@pkill -x AIMeter 2>/dev/null || true
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "build/$(APP_NAME).app" "$(INSTALL_DIR)/"
	@open "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "裝到 $(INSTALL_DIR)/$(APP_NAME).app"
	@echo "設定在面板下方（選單列顯示、更新頻率、開機啟動）"

uninstall:
	@pkill -x AIMeter 2>/dev/null || true
	@launchctl bootout gui/$$(id -u)/$(BUNDLE_ID) 2>/dev/null || true
	@rm -f "$(PLIST)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "移除完成"

clean:
	swift package clean
	@rm -rf build
