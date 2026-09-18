// Page copy, one object per language. English is also in the HTML so the page
// reads without JavaScript. Keys ending in ".html" may contain <br>.
export const LOCALES = {
  en: {
    name: "English",
    fonts: null,
    "meta.title": "Xeneon Toolbox",
    "meta.description": "Turn the Corsair Xeneon Edge into a touch dashboard, launcher and control deck for your Mac. Free, open source, macOS 14 or later.",
    "canvas.label": "A 3D Xeneon Edge running Xeneon Toolbox. Scrolling moves the camera; tapping the screen sends a touch.",
    boot: "Powering on",
    "top.sound": "Sound", "top.download": "Download", "top.language": "Language",
    "rail.hero": "Power on", "rail.strip": "The strip", "rail.apart": "Touch", "rail.tiles": "Tiles", "rail.night": "Night", "rail.land": "Install",
    "label.glass": "Cover glass", "label.glass.sub": "capacitive multi-touch",
    "label.screen": "Panel", "label.screen.sub": "2560 × 720",
    "label.housing": "Housing", "label.housing.sub": "one USB-C cable",
    "hero.h1a": "Your Mac,", "hero.h1b": "on the Edge.",
    "hero.lede": "Xeneon Toolbox turns Corsair's Xeneon Edge into a touch panel for your Mac: a dashboard, an app launcher and a set of controls, drawn for a 2560 × 720 strip.",
    "hero.cta": "Download for macOS", "hero.source": "View the source",
    "hero.note": "Version {v}. Free and open source. Needs macOS 14 or later.",
    "hero.hint": "Tap the screen. Scroll to move the camera.",
    "strip.0.title": "Dashboard", "strip.0.body": "Processor, memory, network, temperatures, weather, your calendar, your tasks and the song that's playing. Eighteen tiles to arrange on a two-row board, readable from across the desk.",
    "strip.1.title": "Deck", "strip.1.body": "A launcher you set up with your thumb. Buttons open apps and sites, fire hotkeys, run shell commands or call a webhook, and you can chain several into one tap.",
    "strip.2.title": "Clock", "strip.2.body": "World clocks, a focus timer, and a bar that shows how far through the day you are.",
    "strip.3.title": "Assistant", "strip.3.body": "Ask by voice or keyboard. It opens apps, checks on the system, looks things up and sets reminders, and it asks before doing anything risky. Works with any OpenAI-compatible endpoint, including models running on your own Mac.",
    "strip.4.title": "Control centre", "strip.4.body": "Wi-Fi, Bluetooth, dark mode, brightness, sound output and playback, one swipe down from the top-right corner.",
    "strip.5.title": "Boost", "strip.5.body": "Shows which background apps are eating memory and quits the ones you pick. It doesn't pretend to clean your RAM.",
    "apart.idx": "Touch", "apart.title.html": "A real touch driver.<br>No kernel extension.",
    "apart.p1": "macOS treats the Edge as a generic pointing device, so taps land in the wrong place. The Toolbox reads the touch controller directly. Taps land where your finger is, two fingers scroll and pinch, and swipes from the edges switch screens.",
    "apart.p2": "Lift your finger and the pointer returns to where you were working on the other display.",
    "tiles.0.idx": "Instruments", "tiles.0.title": "Gauges built from ticks", "tiles.0.body": "Forty-eight ticks across 270 degrees, drawn by the GPU. With every gauge live, the app uses under one percent of a core.",
    "tiles.1.idx": "Up next", "tiles.1.title": "The rest of your day", "tiles.1.body": "Today's remaining events from Calendar, with the current one lit. Tap for the full agenda.",
    "tiles.2.idx": "Running", "tiles.2.title": "Every open app, one tap away", "tiles.2.body": "Tap an icon to bring that app forward. Press and hold to send its window to another display.",
    "tiles.3.idx": "Now playing", "tiles.3.title": "What's on", "tiles.3.body": "Artwork, scrubbing and transport for Spotify and Music. It listens for changes instead of polling.",
    "tiles.4.idx": "Yours", "tiles.4.title": "Arrange it your way", "tiles.4.body": "Tiles come small, wide or tall. Press and hold the board to move, resize, remove or add them. The layout is saved.",
    "night.idx": "Ambient", "night.title.html": "A quiet clock for the hours<br>you're not looking.",
    "night.body": "Swipe down from the top and the strip dims to a clock with your next event, the weather and the music. Tap to wake it. Updates install while it's idle.",
    "land.title": "Set up in about a minute",
    "land.s1.title": "Download it and drag it to Applications", "land.s1.body": "It's a single app, notarized by Apple. Nothing runs as root.",
    "land.s2.title": "Allow Input Monitoring and Accessibility", "land.s2.body": "The app asks for both. If macOS doesn't show a prompt, it opens the right pane in System Settings and notices when you flip the switch.",
    "land.s3.title": "Let it set the resolution", "land.s3.body": "macOS usually picks a scaled mode for the Edge. One tap switches to the native 2560 × 720, and you can undo it.",
    "land.note": "Requires a Corsair Xeneon Edge and macOS 14 or later. Runs on Apple silicon and Intel.",
    "foot.made": "Made in London by Shadow Husky", "foot.source": "Source", "foot.releases": "Releases", "foot.issues": "Issues", "foot.coffee": "Buy me a coffee",
  },

  "zh-Hans": {
    name: "简体中文",
    fonts: "ZCOOL+QingKe+HuangYou&family=Noto+Sans+SC:wght@400;500;700",
    "meta.title": "Xeneon Toolbox",
    "meta.description": "把海盗船 Xeneon Edge 变成 Mac 的触控仪表盘、启动器和控制面板。免费开源，支持 macOS 14 及更高版本。",
    "canvas.label": "一台运行 Xeneon Toolbox 的 3D Xeneon Edge。滚动页面会移动镜头，点按屏幕会触发一次触控。",
    boot: "正在开机",
    "top.sound": "声音", "top.download": "下载", "top.language": "语言",
    "rail.hero": "开机", "rail.strip": "长屏", "rail.apart": "触控", "rail.tiles": "小组件", "rail.night": "夜间", "rail.land": "安装",
    "label.glass": "盖板玻璃", "label.glass.sub": "电容式多点触控",
    "label.screen": "面板", "label.screen.sub": "2560 × 720",
    "label.housing": "机身", "label.housing.sub": "一根 USB-C 线",
    "hero.h1a": "你的 Mac，", "hero.h1b": "触手可及。",
    "hero.lede": "Xeneon Toolbox 把海盗船 Xeneon Edge 变成 Mac 的触控面板：仪表盘、应用启动器和一组快捷控制，专为这条 2560 × 720 的长屏设计。",
    "hero.cta": "下载 macOS 版", "hero.source": "查看源代码",
    "hero.note": "{v} 版，免费开源，需要 macOS 14 或更高版本。",
    "hero.hint": "点一下屏幕试试。向下滚动，镜头会跟着移动。",
    "strip.0.title": "仪表盘", "strip.0.body": "处理器、内存、网络、温度、天气、日程、待办，还有正在播放的歌。十八种小组件随你摆放，上下两行排开，隔着桌子也看得清。",
    "strip.1.title": "快捷面板", "strip.1.body": "用拇指就能搭好的启动器。按钮可以打开应用和网站、触发快捷键、运行 Shell 命令或调用 Webhook，还能把几个动作串成一次点按。",
    "strip.2.title": "时钟", "strip.2.body": "世界时钟、专注计时器，还有一条进度条，告诉你今天已经过去了多少。",
    "strip.3.title": "助手", "strip.3.body": "说话或打字都行。它能打开应用、查看系统状态、上网查资料、设置提醒，遇到有风险的操作会先征求你的同意。支持任何兼容 OpenAI 的接口，包括跑在你自己 Mac 上的本地模型。",
    "strip.4.title": "控制中心", "strip.4.body": "Wi-Fi、蓝牙、深色模式、亮度、声音输出和播放控制，从右上角向下一划就到。",
    "strip.5.title": "加速", "strip.5.body": "看看哪些后台应用最占内存，选中就能退出。不玩“清理内存”那种噱头。",
    "apart.idx": "触控", "apart.title.html": "真正的触控驱动，<br>不需要内核扩展。",
    "apart.p1": "macOS 只把 Edge 当成普通的指点设备，所以点哪儿都不准。Toolbox 直接读取触控芯片的数据：手指点在哪，就响应在哪；双指可以滚动和缩放，从屏幕边缘滑入可以切换页面。",
    "apart.p2": "手指一抬，光标就回到你在另一块屏幕上原来的位置。",
    "tiles.0.idx": "仪表", "tiles.0.title": "用刻度画出来的仪表", "tiles.0.body": "270 度的弧上排着 48 格刻度，全部交给 GPU 绘制。所有仪表同时运行，占用也不到一个核心的 1%。",
    "tiles.1.idx": "接下来", "tiles.1.title": "今天还剩什么安排", "tiles.1.body": "显示日历里今天余下的日程，正在进行的那一项会亮起来。点一下查看全天安排。",
    "tiles.2.idx": "运行中", "tiles.2.title": "每个打开的应用，一点就到", "tiles.2.body": "点图标把应用调到前台，长按可以把它的窗口送到另一块屏幕。",
    "tiles.3.idx": "正在播放", "tiles.3.title": "现在放的是什么", "tiles.3.body": "Spotify 和“音乐”的封面、进度和播放控制。靠系统事件更新，而不是不停轮询。",
    "tiles.4.idx": "自定义", "tiles.4.title": "按你的习惯来摆", "tiles.4.body": "小组件有小、宽、高三种尺寸。长按面板就能移动、缩放、删除或添加，布局会自动保存。",
    "night.idx": "待机", "night.title.html": "不看它的时候，<br>它就是一只安静的钟。",
    "night.body": "从顶部向下一划，长屏就会暗下来，只留时间、下一个日程、天气和音乐。点一下就能唤醒。更新也会趁它闲着的时候装好。",
    "land.title": "一分钟装好",
    "land.s1.title": "下载，拖进“应用程序”", "land.s1.body": "只有一个 App，已通过 Apple 公证，不需要 root 权限。",
    "land.s2.title": "允许“输入监控”和“辅助功能”", "land.s2.body": "App 会主动申请这两项权限。如果 macOS 没有弹窗，它会直接打开“系统设置”里对应的页面，你一打开开关它就知道了。",
    "land.s3.title": "让它调好分辨率", "land.s3.body": "macOS 通常会给 Edge 选一个缩放分辨率。点一下即可切换到原生的 2560 × 720，不合适还能撤销。",
    "land.note": "需要海盗船 Xeneon Edge 和 macOS 14 或更高版本，Apple 芯片和 Intel 机型都支持。",
    "foot.made": "Shadow Husky 制作于伦敦", "foot.source": "源代码", "foot.releases": "版本发布", "foot.issues": "问题反馈", "foot.coffee": "请我喝杯咖啡",
  },

  "zh-Hant": {
    name: "繁體中文",
    fonts: "Noto+Sans+TC:wght@400;500;700",
    "meta.title": "Xeneon Toolbox",
    "meta.description": "把海盜船 Xeneon Edge 變成 Mac 的觸控儀表板、啟動器和控制面板。免費且開放原始碼，支援 macOS 14 以上版本。",
    "canvas.label": "一台執行 Xeneon Toolbox 的 3D Xeneon Edge。捲動頁面會移動鏡頭，點按螢幕會觸發一次觸控。",
    boot: "正在開機",
    "top.sound": "聲音", "top.download": "下載", "top.language": "語言",
    "rail.hero": "開機", "rail.strip": "長螢幕", "rail.apart": "觸控", "rail.tiles": "小工具", "rail.night": "夜間", "rail.land": "安裝",
    "label.glass": "保護玻璃", "label.glass.sub": "電容式多點觸控",
    "label.screen": "面板", "label.screen.sub": "2560 × 720",
    "label.housing": "機身", "label.housing.sub": "一條 USB-C 線",
    "hero.h1a": "你的 Mac，", "hero.h1b": "觸手可及。",
    "hero.lede": "Xeneon Toolbox 把海盜船 Xeneon Edge 變成 Mac 的觸控面板：儀表板、App 啟動器和一組快速控制，專為這條 2560 × 720 的長螢幕設計。",
    "hero.cta": "下載 macOS 版", "hero.source": "查看原始碼",
    "hero.note": "{v} 版，免費且開放原始碼，需要 macOS 14 或以上版本。",
    "hero.hint": "點一下螢幕試試。往下捲動，鏡頭會跟著移動。",
    "strip.0.title": "儀表板", "strip.0.body": "處理器、記憶體、網路、溫度、天氣、行事曆、待辦事項，還有正在播放的歌。十八種小工具隨你排列，上下兩列，隔著桌子也看得清楚。",
    "strip.1.title": "快捷面板", "strip.1.body": "用拇指就能搭好的啟動器。按鈕可以打開 App 和網站、觸發快速鍵、執行 Shell 指令或呼叫 Webhook，還能把幾個動作串成一次點按。",
    "strip.2.title": "時鐘", "strip.2.body": "世界時鐘、專注計時器，還有一條進度列，告訴你今天已經過了多少。",
    "strip.3.title": "助理", "strip.3.body": "用說的或用打的都行。它能打開 App、查看系統狀態、上網查資料、設定提醒事項，遇到有風險的操作會先問過你。支援任何相容 OpenAI 的端點，包括在你自己 Mac 上執行的本機模型。",
    "strip.4.title": "控制中心", "strip.4.body": "Wi-Fi、藍牙、深色模式、亮度、聲音輸出和播放控制，從右上角往下一滑就到。",
    "strip.5.title": "加速", "strip.5.body": "看看哪些背景 App 最吃記憶體，選起來就能結束。不玩「清理記憶體」那種噱頭。",
    "apart.idx": "觸控", "apart.title.html": "真正的觸控驅動程式，<br>不需要核心延伸功能。",
    "apart.p1": "macOS 只把 Edge 當成一般的指標裝置，所以點哪裡都不準。Toolbox 直接讀取觸控晶片的資料：手指點在哪，就回應在哪；兩指可以捲動和縮放，從螢幕邊緣滑入可以切換頁面。",
    "apart.p2": "手指一離開，游標就回到你在另一個螢幕上原本的位置。",
    "tiles.0.idx": "儀表", "tiles.0.title": "用刻度畫出來的儀表", "tiles.0.body": "270 度的弧上排著 48 格刻度，全部交給 GPU 繪製。所有儀表同時運作，用量也不到一個核心的 1%。",
    "tiles.1.idx": "接下來", "tiles.1.title": "今天還有哪些行程", "tiles.1.body": "顯示行事曆裡今天剩下的行程，正在進行的那一項會亮起來。點一下查看整天的安排。",
    "tiles.2.idx": "執行中", "tiles.2.title": "每個打開的 App，一點就到", "tiles.2.body": "點圖像把 App 帶到最前面，長按可以把它的視窗送到另一個螢幕。",
    "tiles.3.idx": "播放中", "tiles.3.title": "現在放的是什麼", "tiles.3.body": "Spotify 和「音樂」的封面、進度和播放控制。靠系統事件更新，而不是不停輪詢。",
    "tiles.4.idx": "自訂", "tiles.4.title": "照你的習慣來排", "tiles.4.body": "小工具有小、寬、高三種尺寸。長按面板就能移動、調整大小、刪除或加入，版面會自動儲存。",
    "night.idx": "待機", "night.title.html": "不看它的時候，<br>它就是一座安靜的鐘。",
    "night.body": "從頂端往下一滑，長螢幕就會暗下來，只留下時間、下一個行程、天氣和音樂。點一下就能喚醒。更新也會趁它閒著的時候裝好。",
    "land.title": "一分鐘裝好",
    "land.s1.title": "下載，拖進「應用程式」", "land.s1.body": "只有一個 App，已通過 Apple 公證，不需要 root 權限。",
    "land.s2.title": "允許「輸入監控」和「輔助使用」", "land.s2.body": "App 會主動要求這兩項權限。如果 macOS 沒有跳出對話框，它會直接打開「系統設定」裡對應的頁面，你一打開開關它就知道了。",
    "land.s3.title": "讓它調好解析度", "land.s3.body": "macOS 通常會替 Edge 選一個縮放解析度。點一下就能切換到原生的 2560 × 720，不合適還能還原。",
    "land.note": "需要海盜船 Xeneon Edge 和 macOS 14 或以上版本，Apple 晶片和 Intel 機型都支援。",
    "foot.made": "Shadow Husky 製作於倫敦", "foot.source": "原始碼", "foot.releases": "版本發佈", "foot.issues": "問題回報", "foot.coffee": "請我喝杯咖啡",
  },

  ja: {
    name: "日本語",
    fonts: "Noto+Sans+JP:wght@400;500;700",
    "meta.title": "Xeneon Toolbox",
    "meta.description": "Corsair Xeneon Edge を、Mac 用のタッチダッシュボード、ランチャー、コントロールパネルに。無料のオープンソース、macOS 14 以降に対応。",
    "canvas.label": "Xeneon Toolbox が動作している Xeneon Edge の 3D モデル。スクロールするとカメラが動き、画面をタップするとタッチが送られます。",
    boot: "起動中",
    "top.sound": "サウンド", "top.download": "ダウンロード", "top.language": "言語",
    "rail.hero": "起動", "rail.strip": "横長画面", "rail.apart": "タッチ", "rail.tiles": "タイル", "rail.night": "夜", "rail.land": "インストール",
    "label.glass": "カバーガラス", "label.glass.sub": "静電容量式マルチタッチ",
    "label.screen": "パネル", "label.screen.sub": "2560 × 720",
    "label.housing": "筐体", "label.housing.sub": "USB-C ケーブル 1 本",
    "hero.h1a": "Macを、", "hero.h1b": "指先ひとつで。",
    "hero.lede": "Xeneon Toolbox は、Corsair の Xeneon Edge を Mac 用のタッチパネルに変えるアプリです。ダッシュボード、アプリランチャー、各種コントロールを、2560 × 720 の横長画面に合わせて作りました。",
    "hero.cta": "macOS 版をダウンロード", "hero.source": "ソースコードを見る",
    "hero.note": "バージョン {v}。無料のオープンソースです。macOS 14 以降が必要です。",
    "hero.hint": "画面をタップしてみてください。スクロールするとカメラが動きます。",
    "strip.0.title": "ダッシュボード", "strip.0.body": "CPU、メモリ、ネットワーク、温度、天気、予定、タスク、そして再生中の曲。18 種類のタイルを 2 段のボードに自由に並べられ、机の向こうからでも読み取れます。",
    "strip.1.title": "デッキ", "strip.1.body": "親指ひとつで組めるランチャー。ボタンからアプリやサイトを開いたり、ショートカットキーを送ったり、シェルコマンドや Webhook を実行できます。複数の操作をワンタップにまとめることも。",
    "strip.2.title": "時計", "strip.2.body": "世界時計、集中タイマー、そして今日がどこまで進んだかを示すバー。",
    "strip.3.title": "アシスタント", "strip.3.body": "声でもキーボードでも。アプリを開き、システムの状態を確認し、調べものをして、リマインダーも設定します。リスクのある操作は必ず先に確認します。OpenAI 互換のエンドポイントならどれでも使え、手元の Mac で動くローカルモデルにも対応します。",
    "strip.4.title": "コントロールセンター", "strip.4.body": "Wi-Fi、Bluetooth、ダークモード、明るさ、音声出力、再生コントロール。右上から下へスワイプするだけです。",
    "strip.5.title": "ブースト", "strip.5.body": "メモリを多く使っているバックグラウンドのアプリを表示し、選んだものだけを終了します。「メモリ解放」のようなごまかしはしません。",
    "apart.idx": "タッチ", "apart.title.html": "本物のタッチドライバ。<br>カーネル拡張は不要。",
    "apart.p1": "macOS は Edge をただのポインティングデバイスとして扱うため、タップした場所がずれてしまいます。Toolbox はタッチコントローラを直接読み取るので、指を置いた場所がそのまま反応します。2 本指でスクロールとピンチ、画面の端からのスワイプで画面の切り替えもできます。",
    "apart.p2": "指を離すと、ポインタは別のディスプレイで作業していた元の位置に戻ります。",
    "tiles.0.idx": "メーター", "tiles.0.title": "目盛りで描くゲージ", "tiles.0.body": "270 度の弧に 48 本の目盛り。描画は GPU に任せているので、すべてのゲージを動かしていても CPU 使用率は 1 コアの 1% 未満です。",
    "tiles.1.idx": "次の予定", "tiles.1.title": "今日の残りの予定", "tiles.1.body": "カレンダーから今日これからの予定を表示し、進行中のものは点灯します。タップすると一日の予定を確認できます。",
    "tiles.2.idx": "実行中", "tiles.2.title": "開いているアプリへ、ワンタップで", "tiles.2.body": "アイコンをタップするとそのアプリが前面に。長押しすると、ウインドウを別のディスプレイへ送れます。",
    "tiles.3.idx": "再生中", "tiles.3.title": "いま流れている曲", "tiles.3.body": "Spotify とミュージックのアートワーク、シーク、再生コントロール。ポーリングではなく、変更の通知を受けて更新します。",
    "tiles.4.idx": "カスタマイズ", "tiles.4.title": "好きなように並べる", "tiles.4.body": "タイルは小・ワイド・トールの 3 サイズ。ボードを長押しすると、移動、サイズ変更、削除、追加ができます。レイアウトは自動で保存されます。",
    "night.idx": "アンビエント", "night.title.html": "見ていないときは、<br>静かな時計に。",
    "night.body": "上端から下へスワイプすると、画面が暗くなり、時刻と次の予定、天気、音楽だけが残ります。タップで元に戻ります。アップデートは、使っていない間に済ませます。",
    "land.title": "1 分でセットアップ",
    "land.s1.title": "ダウンロードして「アプリケーション」へ", "land.s1.body": "アプリはひとつだけ。Apple の公証済みで、root 権限は使いません。",
    "land.s2.title": "「入力監視」と「アクセシビリティ」を許可", "land.s2.body": "どちらもアプリ側からリクエストします。macOS のダイアログが出ないときは、システム設定の該当ページを開き、スイッチを入れた瞬間に検知します。",
    "land.s3.title": "解像度の調整はおまかせ", "land.s3.body": "macOS は Edge にスケーリングされた解像度を選びがちです。ワンタップでネイティブの 2560 × 720 に切り替わり、元に戻すこともできます。",
    "land.note": "Corsair Xeneon Edge と macOS 14 以降が必要です。Apple シリコンと Intel の両方に対応。",
    "foot.made": "ロンドンにて、Shadow Husky 制作", "foot.source": "ソース", "foot.releases": "リリース", "foot.issues": "不具合の報告", "foot.coffee": "コーヒーをおごる",
  },
};

const STORE = "xt.lang";
let current = "en", version = "1.18.0";

/** The visitor's language: an explicit ?lang=, then their last choice, then the system's list. */
export function detect() {
  const asked = new URLSearchParams(location.search).get("lang");
  let saved = null; try { saved = localStorage.getItem(STORE); } catch {}
  for (const tag of [asked, saved, ...(navigator.languages || [navigator.language])]) {
    const code = match(tag); if (code) return code;
  }
  return "en";
}

function match(tag) {
  if (!tag) return null;
  const t = tag.toLowerCase();
  if (t.startsWith("zh")) return /hant|tw|hk|mo/.test(t) ? "zh-Hant" : "zh-Hans";
  if (t.startsWith("ja")) return "ja";
  if (t.startsWith("en")) return "en";
  return LOCALES[tag] ? tag : null;
}

export function setVersion(v) { version = String(v).replace(/^v/i, ""); apply(current, false); }

export function apply(code, remember = true) {
  const L = LOCALES[code] || LOCALES.en; current = LOCALES[code] ? code : "en";
  const t = (key) => (L[key] ?? LOCALES.en[key] ?? "").replace("{v}", version);
  document.documentElement.lang = current;
  document.title = t("meta.title");
  document.querySelector('meta[name="description"]')?.setAttribute("content", t("meta.description"));
  document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n); });
  document.querySelectorAll("[data-i18n-html]").forEach((el) => { el.innerHTML = t(el.dataset.i18nHtml); });
  document.querySelectorAll("[data-i18n-label]").forEach((el) => { el.setAttribute("aria-label", t(el.dataset.i18nLabel)); });
  if (L.fonts && !document.getElementById(`font-${current}`)) {
    const link = Object.assign(document.createElement("link"), { id: `font-${current}`, rel: "stylesheet",
      href: `https://fonts.googleapis.com/css2?family=${L.fonts}&display=swap` });
    document.head.appendChild(link);
  }
  const name = document.getElementById("lang-name"); if (name) name.textContent = L.name;
  document.querySelectorAll("[data-lang]").forEach((b) => b.setAttribute("aria-checked", String(b.dataset.lang === current)));
  if (remember) { try { localStorage.setItem(STORE, current); } catch {} }
  dispatchEvent(new Event("resize"));   // caption heights change with the language; the scene re-measures
}

export function initLanguage() {
  apply(detect(), false);
  const wrap = document.getElementById("lang"), btn = document.getElementById("lang-btn"), menu = document.getElementById("lang-menu");
  if (!wrap) return;
  const close = () => { menu.hidden = true; btn.setAttribute("aria-expanded", "false"); };
  btn.addEventListener("click", () => { menu.hidden = !menu.hidden; btn.setAttribute("aria-expanded", String(!menu.hidden)); });
  menu.addEventListener("click", (e) => { const b = e.target.closest("[data-lang]"); if (b) { apply(b.dataset.lang); close(); btn.focus(); } });
  addEventListener("click", (e) => { if (!wrap.contains(e.target)) close(); });
  addEventListener("keydown", (e) => { if (e.key === "Escape") close(); });
}
