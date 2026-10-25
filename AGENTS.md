# AGENTS.md

Aura —— WebKit 的 macOS 浏览器，[Search](https://github.com/driceroland/Search)（Office Commun，MIT）的 fork：Swift + AppKit/SwiftUI 单进程、零第三方依赖；界面以英文原文为键，简体中文放在 `Resources/zh-Hans.lproj`。

动手前先读对应的家，不要凭记忆：

- `README.md` — 是什么、怎么构建、更新源在哪
- `CONTRIBUTING.md` — 什么样的改动会合并；新功能三条（最小、默认关、能找到）；翻译入表的两个入口
- `CHANGELOG.md` — **`Unreleased` 是行为现状态**：想知道某个功能今天怎么工作，先读这里
- `ROADMAP.md` — 需求从哪来（由 `./ideas` 从 officecommun 的库生成，勿手改）
- `skill/aura-bench/SKILL.md` — 用 `./bench` 驱动浏览器时的世界隔离规矩

## 心法

- **主流写法，不自造轮子**：这是一个人的浏览器，代码短、直白、可读优先；宁可朴素，不可聪明。
- **一文件一职责**：`Sources/Aura` 平铺，文件名就是它管的那唯一一件事；新功能先问要不要一个新文件。
- **只写当下需要的**：不做未来预留、不留注释掉的代码、不留"以后可能用得上"的开关。
- **目录即地图**：新文件开头一段散文注释交代管什么、为什么这么设计（样板：`Browser.swift`、`Design.swift`、`Localized.swift`）。

## 仓库布局

```
Sources/Aura/                120 个 Swift 文件平铺；Design.swift 是颜色与材质的唯一事实源
Resources/zh-Hans.lproj/Localizable.strings   中文译文（英文原文即键）
Tests/AuraTests/             XCTest 单测（swift test）
Tests/*.py                   隐藏探针界面测试：先 ./build.sh，再 python3 跑
Tests/*Regression/           用 swiftc 直接编译几个源文件的回归跑器，各自带 run.sh
Engine/                      AI 引擎源码与沙盒 entitlements（./engine.sh 构建进 build/engine/）
Icon/  Installer/            logo 种子（Tools/mark.py 写进 AuraMark.swift）、DMG 背景
build.sh  fresh.sh  engine.sh  publish.sh  tap.sh  bench  ideas      根目录脚本，头部注释即用法
Tools/i18n.py  Tools/mark.py  Tools/filters.py                     翻译扫描 / logo 路径生成 / 过滤表转成规则表
Resources/Shield/            生成的 network/extra/cosmetic.json.z（前 4 字节原大小，其余 raw deflate），Shield.swift 解开交 WebKit；
                             scriptlets.json.z 与 scriptlets.js 是注入页面回答反广告检测的那层（Scriptlets.swift）；
                             sources.json 记来源，LICENSES.md 与 GPL-3.0.txt 记授权
Aura.sdef                    AppleScript 字典；实现是 Scripting.swift，build.sh 放进 bundle
VERSION                      版本号；发版才动，前两位由用户定
```

## 命令

```sh
./build.sh                                # build/Aura.app，ad-hoc 签名，能直接跑
./build.sh release dmg                    # + build/Aura.dmg、Aura.zip、appcast.json
./build.sh release ship                   # + 公证与装钉（Developer ID + notarytool profile "aura"）
AURA_ARCH=x86_64 ./build.sh release dmg   # Intel 档，出 build/intel/

swift build                               # 只编译二进制；要保证零新增警告
swift test                                # Tests/AuraTests（XCTest）

./fresh.sh                                # 抹掉测试世界，以新用户身份启动（不碰你在用的浏览器）
./fresh.sh again                          # 沿用测试世界再启动
AURA_PROBE=<slug> ./fresh.sh              # 一条并行的活一个世界（Aura (<slug>)），互不抢 bench socket
./bench help                              # 驱动运行中的 app 的全部命令；改动界面加 --test
python3 Tests/<probe>.py                  # 隐藏探针（先 ./build.sh）；--app PATH 指向另一个构建
./Tests/AddressRegression/run.sh          # 注意：脚本里的源码路径已失效，见「已知遗留」

./Tools/i18n.py scan | missing | check    # 键从哪来 / 缺什么 / 缺了就失败
plutil -lint Resources/*/Localizable.strings
./engine.sh [arm64|x86_64]                # AI 引擎（llama.cpp 固定 commit，static，沙盒签名）
./ideas [md]                              # 维护 ROADMAP（写回 officecommun 的库）
./publish.sh ../aura-pages                # 把三个文件放进 Pages worktree；发版才做
./tap.sh                                  # 把刚发布的版本写进 Homebrew tap；发版才做
gitleaks git --pre-commit --staged        # 提交前扫密钥（.gitleaks.toml）

git worktree add ../Aura-<slug> -b feat/<slug>   # 开一棵任务树，改动全在树里做
git worktree remove ../Aura-<slug>               # 收尾清场，再 git branch -d feat/<slug>
./hooks.sh [on|off]                              # 机械卡点：主仓检出上拒收直接提交（不带参数＝看状态）
```

## 并行任务：一棵树一个世界

- **一个任务一棵树**：`git worktree add ../Aura-<slug> -b feat/<slug>` 动手，主仓（`main` 的检出）只收 `git merge --no-ff feat/<slug>`（一个任务一个合并提交），收尾 `git worktree remove` + `git branch -d`，不留残树。
- **机械卡点已装**（`./hooks.sh on`，`core.hooksPath` 指向 `.git-hooks/`）：主仓检出上的 `git commit` 直接被拒；worktree 里照常，收尾合并（`MERGE_HEAD` 在）放行，真要在主仓直接提交用 `git commit --no-verify`（绕过得是显式动作）。配置在共享 config 里，一棵树启用、所有树生效。
- **一棵树一个测试世界**：`./fresh.sh` 与 `./bench --test` 用的是固定的 `test` 世界，两棵树同时用会撞在同一个 `Aura (test)` 上——同一个 bundle id、同一个 WebKit store、同一个 bench socket，后开的把前一个顶掉。并行时各自起名：`AURA_PROBE=<slug> ./fresh.sh` 配 `./bench --world <slug>`。`Tests/*.py` 探针不用管：它们按检出路径自己分世界（`AURA_PROBE=<suite>-<checkout 哈希>`，见 `Tests/split_view.py` 的 `use()`）。
- **`../aura-pages` 不是任务树**：那是 `gh-pages` 的检出，`publish.sh` 认这个路径；别拿它当工作区，也别删。
- **新树的 `.build/` 是冷的**：第一次 `swift build` 从头编译，属正常；不为省时间在两棵树间共享构建目录（一个任务一棵树的意义就在于两棵互不干扰）。
- **提交前 `git status` 复核**，只 `git add` 本轮文件——工作区长期有 WIP，别把别人的改动卷进你的提交。

## 完成的定义：测试与交付

- `swift build` 零新增警告；纯逻辑改动（地址、历史、扩展 shim 一类）跑 `swift test` 或对应的 `Tests/*Regression/run.sh`。测试红且与本次改动相关，就带着输出停下报告，不在同一处反复重跑。
- **自证用测试世界，验收归用户**：对不对、好不好看由人在真机上看。agent 交付到「`./build.sh` 过了、`build/Aura.app` 是新的」为止——不自行截图当验收、不擅自替换 `/Applications/Aura.app`、不擅自 `release dmg`/`ship`/`publish.sh`/`tap.sh`/动 `VERSION`。
- **世界由启动方式决定**（`Store.swift`）：`AURA_PROBE` 有值、或可执行文件在 `/.build/` 下的，一律是测试世界；`build/Aura.app` 不带 `AURA_PROBE` 就是**真身**，读写用户在用的那份数据。
- **不碰用户在用的浏览器**：`./bench` 不带 flag 连的是真身（`~/Library/Application Support/Aura`）。改界面、装扩展、窗口尺寸、真键盘事件一律 `--test` 或 `--world <name>`；真身上只 `tabs`/`probe`/页面命令，且只在用户点名时。
- **测试世界的纪律**（细节见 `skill/aura-bench/SKILL.md`）：一个世界同时只发一条 `./bench` 命令（约 25 秒超时）；自己开的 bench tab 自己关；`./fresh.sh` 只在用户要「干净的浏览器」时抹世界；进程要隐藏着起，顶到前台会让探针拒掉整轮命令。
- **交付链**：`./build.sh` → 退出正在跑的那个 Aura（同 bundle id、同一个世界，先退再开，否则验收的是旧实例）→ 用户自己开 `build/Aura.app`。起不来看 `~/Library/Application Support/Aura/crash.log`。
- 改变行为的改动，同轮在 `CHANGELOG.md` 的 `Unreleased` 补一行；`NOTES.md` 只在发版时写（第一段进 appcast）。
- 提交信息中文，一句讲清做了什么、为什么；临时探针、`AURA_MEASURE`、临时 `defaults` 当轮撤干净。

## 工程铁律

1. **只修用户指出的问题**：不扩大范围，不顺手"根除"别处。
2. **不加第三方依赖**（CONTRIBUTING 定的）：Foundation / WebKit 能做的就自己做；要加先停下来问用户。
3. **不发没说过的话到网上**：任何新的出网行为都要有用户看得见的开关与说明；AI 相关默认关闭，总闸是 `AI.shipped`。
4. **新功能默认关闭、最小、能在设置里找到**（CONTRIBUTING 三条）；浏览器本来就该有的（Tab 在表单字段间跳、⌘1–⌘9）例外。
5. **可失败的读取不用 `!`**：网络响应、文件、钥匙串一律显式 `guard let` / `try?`；`!` 只给不可能失败的（刚写进去的键、枚举穷尽的分支）。
6. **不 vendored 引擎**：这是 WebKit 浏览器，页面能力只走 WebKit 公开 API。
7. **密钥不入库**：代码、测试、issue、日志里都不写真的 key；测试用一眼假的。
8. **"没生效"先读代码与产物**：`git status` → 读改动 → 看 `build/Aura.app` 里实际是什么；不拿"没重启 / 旧实例"打发用户。
9. **不确定就问**：字段名、契约、行为含义有疑问先查事实源（源码注释、CHANGELOG、WebKit 头文件），查不到就问，不写猜测性代码。
10. **删就删干净**：删功能时把代码、译文键、设置项、菜单项、CHANGELOG 行、ROADMAP 条目一起处理。

## 代码约定

- 新增功能 = 新增文件（或一对），名字就是它管的那件事；别往 `Browser.swift` 里续写，除非它确实是 `Browser` 的状态。
- 文件开头一段散文注释：管什么、为什么；文件内用 `// MARK:` 分段。
- 注释写 **why**，不写"下一行在做什么"（CONTRIBUTING）。
- 界面文字只经 `Localized(...)` 或 SwiftUI 字面量（`Text("…")` 会被自动查表）；**裸中文不许进 Swift 源码**。
- 颜色、材质、圆角先在 `Design.swift` 的 `Palette` 里定义再引用；新色值不内联（`Spaces.swift` 里那组空间色是既有例外，别再扩散）。
- 界面全在 main actor，`Package.swift` 把语言模式钉在 Swift 5；别为一堆 `@Sendable` 仪式重排既有结构。
- 一个功能一个入口：设置项进 `Settings.swift` 的分区（`general / tabs / shortcuts / extensions / passwords / downloads / privacy / ai / about`），菜单项进 `App.swift` 的 `CommandMenu`，快捷键走菜单加 `KeyLayout`；不另开第二套。

## 翻译约定

- 英文原文就是键；新增一句英文，同轮补 `Resources/zh-Hans.lproj/Localizable.strings` 的中文。缺了只是回退英文（不崩），但中文界面漏句算没做完。
- 带值的句子写成 `Text(Localized("Search \(version) is downloading…"))`，键是骨架（`"Search {1} is downloading…"`）；中文可以挪动、省略或重复 `{1}`。
- 同一概念全应用同一个词；沿用既有译法，别一句一个新说法。
- 提交前 `plutil -lint Resources/*/Localizable.strings` —— 长句里多打一个引号是常见错误。

## 文档与提交约定

- 提交信息中文（本 fork 自 `6295120` 起），一句讲因果，细节放正文。
- 文档**现状态写作**：正文写"是什么"，变更史归 `CHANGELOG.md` 与 commit；不写 previously / now / "已实现！"。
- 一事一家：同一事实只有一个文件拥有，别处链接。
- **推送前看 remote**：`main` 跟踪 `origin`（上游 `driceroland/Search`），本 fork 的库叫 `aura` —— 推自己的改动用 `git push aura main`。

## 已知遗留（实测，别踩）

- **改名遗留**：`Tests/AddressRegression/run.sh`、`Tests/HistoryRegression/run.sh`、`Tests/DuskHarness.swift`、`Tests/popup_gesture_script.js`、`Tests/ExtensionWorkerRecovery/run.js` 里仍写 `Sources/Search/…`，源码已在 `Sources/Aura/` —— 直接跑报 `No such file`。要修就修脚本，**不要**建 `Sources/Search` 兼容目录。
- **引擎命名两套**：源码是 `Engine/aura-ai-engine.cpp`，`engine.sh` 的产物是 `aura-ai-engine-<arch>`，而运行时找的下载程序叫 `search-ai-engine`；以 `engine.sh` 与 `AIEngine.swift` 为准，别按注释里的旧名找文件。
- `AI.shipped = false` 是 AI 附加功能的总闸（1.0.5 起收起）：动 AI 代码前先读这一行，别让它在关着时露出入口。
- 工作区长期有未提交的 WIP（空间主题、Glass 一类）：提交时只 `git add` 本轮文件。

## 维护本文件

每条规则保持 1-3 行并链接到它的家；细节与故事不搬进来（一事一家）。`CLAUDE.md` 是指向本文件的符号链接——编辑本文件，勿编辑链接。
