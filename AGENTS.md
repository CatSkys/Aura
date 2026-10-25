# AGENTS.md

Aura —— WebKit 的 macOS 浏览器，[Search](https://github.com/driceroland/Search)（Office Commun，MIT）的 fork：Swift + AppKit/SwiftUI 单进程、零第三方依赖；界面以英文原文为键，简体中文放在 `Resources/zh-Hans.lproj`。

动手前先读对应的家，不要凭记忆：

- `README.md` — 是什么、怎么构建、更新源在哪
- `CONTRIBUTING.md` — 什么样的改动会合并；新功能三条（最小、默认关、能找到）；翻译入表的两个入口
- `CHANGELOG.md` — **`Unreleased` 是行为现状态**：某个功能今天怎么工作，先读这里
- `ROADMAP.md` — 需求从哪来（`./ideas` 从 officecommun 的库生成，勿手改）
- `skill/aura-bench/SKILL.md` — 用 `./bench` 驱动浏览器时的世界隔离规矩

## 心法

- **主流写法，不自造轮子**：一个人的浏览器，代码短、直白、可读优先；宁可朴素，不可聪明。
- **一文件一职责**：`Sources/Aura` 平铺，文件名就是它管的那唯一一件事；新功能先问要不要一个新文件。
- **只写当下需要的**：不做未来预留、不留注释掉的代码、不留"以后用得上"的开关。
- **目录即地图**：新文件开头一段散文注释交代管什么、为什么（样板：`Browser.swift`、`Design.swift`、`Localized.swift`）。

## 仓库布局

```
Sources/Aura/                120 个 Swift 文件平铺；Design.swift 是颜色与材质的唯一事实源
Resources/zh-Hans.lproj/     中文译文（英文原文即键）
Resources/Shield/            生成的规则表与脚本层：network/extra/cosmetic.json.z、scriptlets.json.z + scriptlets.js、
                             sources.json 与授权（LICENSES.md、GPL-3.0.txt）；Shield.swift / Scriptlets.swift 读它们
Tests/AuraTests/             XCTest 单测（swift test）
Tests/*.py                   隐藏探针（界面行为）：先 ./build.sh，再 python3 跑
Tests/*Regression/           用 swiftc 直接编译几个源文件的回归跑器，各自带 run.sh
Engine/                      AI 引擎源码与沙盒 entitlements（./engine.sh 构建进 build/engine/）
Icon/  Installer/            logo 种子（Tools/mark.py 写进 AuraMark.swift）、DMG 背景
Aura.sdef                    AppleScript 字典；实现是 Scripting.swift，build.sh 放进 bundle
VERSION                      版本号；发版才动，前两位由用户定
```

## 命令

```sh
# 构建
./build.sh                                # build/Aura.app（release，ad-hoc 签名）
./build.sh release dmg | ship             # + DMG/ZIP/appcast；ship 再公证装钉
AURA_ARCH=x86_64 ./build.sh release dmg   # Intel 档，出 build/intel/

# 快速验证 —— 小修走这条：文案、译文、注释、文档、脚本、样式微调
swift build                               # 秒级；要零新增警告

# 全量验证 —— 改行为走这条：Swift 逻辑、WebKit 交互、扩展、拦截规则
swift test                                # Tests/AuraTests 全套（XCTest）
python3 Tests/<名字>.py                   # 只跑受影响的那个探针（先 ./build.sh）
./Tests/AddressRegression/run.sh          # 解析类回归；脚本里的源码路径已失效，见「已知遗留」

# 交付：合并 → 构建 → 清场
./deliver.sh <slug>

# 测试世界与探针
./fresh.sh | ./fresh.sh again             # 测试世界；AURA_PROBE=<slug> 一树一世界
./bench help                              # 驱动运行中的 app；改界面一律加 --test 或 --world

# 译文
./Tools/i18n.py scan | missing | check
plutil -lint Resources/*/Localizable.strings

# 并行与提交
git worktree add ../Aura-<slug> -b feat/<slug>
git worktree remove ../Aura-<slug>        # 收尾再 git branch -d feat/<slug>
./hooks.sh [on|off]                       # 机械卡点：主仓检出拒收直接提交
gitleaks git --pre-commit --staged        # 提交前扫密钥（.gitleaks.toml）

# 发版与外部动作 —— 只在用户明确要求时
./engine.sh [arm64|x86_64]                # AI 引擎（llama.cpp 固定 commit，static，沙盒签名）
./ideas [md]                              # 维护 ROADMAP（写回 officecommun 的库）
./publish.sh ../aura-pages                # 三个文件放进 Pages worktree
./tap.sh                                  # 写进 Homebrew tap
```

## 完成的定义：快速 → 全量 → 交付

- **两种验证，按改动性质选，别混着用**：改文案/译文/注释/文档/脚本/样式微调 → `swift build`（秒级）。改行为（Swift 逻辑、WebKit 交互、扩展、拦截规则）→ `swift test` 全套 + 受影响的那个探针。**拿不准算不算行为改动，按行为改动跑。** 全量的标准是"没有新增失败"，不是"全绿"——既有红在「已知遗留」。
- **测试纪律**：一条命令一次跑完；同一轮最多重跑两次，仍红就带着输出停下报告；探针先确认世界在答（`./bench --test tabs`）再等它。不为一句话改动去跑全量。
- **自证在测试世界，验收归用户**：世界由启动方式决定（`AURA_PROBE` 有值或可执行文件在 `/.build/` 下＝测试世界；`build/Aura.app` 不带变量＝真身）。改界面、装扩展、窗口尺寸、真键盘事件一律 `--test`/`--world`；不自行截图当验收、不擅自换 `/Applications/Aura.app`。
- **交付**：`./deliver.sh <slug>`。只改文档/脚本（不碰 `Sources/`、`Resources/`、`Engine/`、`Package.swift`、`VERSION`）就不重建产物；主仓有别处的活时也不重建。产物只代表主仓 HEAD。
- 改变行为的改动同轮补 `CHANGELOG.md` 的 `Unreleased`；`NOTES.md` 只在发版时写（第一段进 appcast）。
- 提交信息中文，一句讲清因果；临时探针、`AURA_MEASURE`、临时 `defaults` 当轮撤干净。

## 并行任务：一棵树一个世界

- **一个任务一棵树**：`git worktree add ../Aura-<slug> -b feat/<slug>` 动手；主仓只收合并，收尾 `git worktree remove` + `git branch -d`，不留残树。
- **主仓不承接活，但别让分支攒着**：活全在树里。主仓被别的会话占着时，`./deliver.sh` 允许**文件不重叠**的合并先落地（重叠就拒），这次不构建——产物会把那份活编进去。**不许替别人 stash**（教训：为合 `feat/facade` 把 15 个文件的活收起来四分钟，那次构建的产物因此不含那份活）。索引里有 staged 改动时 `git merge` 一律拒收，先让它 unstage。
- **一棵树一个测试世界**：`./fresh.sh` 与 `./bench --test` 用固定的 `test` 世界，两棵树同时用会抢同一个 socket；并行时 `AURA_PROBE=<slug> ./fresh.sh` 配 `./bench --world <slug>`。`Tests/*.py` 按检出路径自己分世界，不用管。
- **`../aura-pages` 不是任务树**：那是 `gh-pages` 的检出，`publish.sh` 认这个路径。
- **新树的 `.build/` 是冷的**：第一次 `swift build` 从头编译，属正常；别在两棵树间共享构建目录。

## 并行交付：一次只合一个

- **合并在锁上排队**：`./deliver.sh <slug>` 先抢 `.git/deliver.lock`（所有树共享一把）。两个交付同时来，第二个停下并指名谁在跑、从几点开始，而不是两边一起写主仓索引。
- **冲突在树里解决**：`git -C ../Aura-<slug> merge main`，在树里解冲突、构建、验证，再交付。`deliver.sh` 用 `git merge-tree` 预演，会冲突就直接拒——主仓永远不出现要人工解的合并。
- **构建失败就撤回合并**（`reset --hard ORIG_HEAD`），树与分支留着；清场失败（树里又长出新东西）一样停下，绝不 `--force` 盖别人的活。
- **一个检出同时只跑一个 `./build.sh`**：SwiftPM 会让后来者等锁，但 `build/Aura.app` 与签名会互相盖；两棵树各有 `.build`，各跑各的没问题。
- **锁只拦交付，不拦手**：锁在时主仓是施工区，谁都不许在里面做手工 git 操作；确认没有交付在跑才 `rm -rf .git/deliver.lock`，永远别删 `index.lock`。

## 工程铁律

1. **只修用户指出的问题**：不扩大范围，不顺手"根除"别处。
2. **不加第三方依赖**（CONTRIBUTING 定的）：Foundation / WebKit 能做的就自己做；要加先停下来问用户。
3. **不发没说过的话到网上**：任何新的出网行为都要有用户看得见的开关与说明；AI 相关默认关闭，总闸是 `AI.shipped`。
4. **新功能默认关闭、最小、能在设置里找到**（CONTRIBUTING 三条）；浏览器本来就该有的（Tab 在表单字段间跳、⌘1–⌘9）例外。
5. **可失败的读取不用 `!`**：网络响应、文件、钥匙串一律显式 `guard let` / `try?`；`!` 只给不可能失败的。
6. **不 vendored 引擎**：这是 WebKit 浏览器，页面能力只走 WebKit 公开 API。
7. **密钥不入库**：代码、测试、issue、日志里都不写真的 key；测试用一眼假的。
8. **"没生效"先读代码与产物**：`git status` → 读改动 → 看 `build/Aura.app` 里实际是什么；不拿"没重启 / 旧实例"打发用户。
9. **不确定就问**：字段名、契约、行为含义有疑问先查事实源（源码注释、CHANGELOG、WebKit 头文件），查不到就问，不写猜测性代码。
10. **删就删干净**：删功能时把代码、译文键、设置项、菜单项、CHANGELOG 行、ROADMAP 条目一起处理。
11. **交付＝提交后跑 `./deliver.sh <slug>`**：停在树里的提交没人看得见；脚本做完合、建、清并打印自检，它拒绝就按它说的先解决，别绕过。

## 代码约定

- 新增功能 = 新增文件（或一对），名字就是它管的那件事；别往 `Browser.swift` 里续写，除非它确实是 `Browser` 的状态。
- 文件开头一段散文注释：管什么、为什么；文件内用 `// MARK:` 分段。
- 注释写 **why**，不写"下一行在做什么"（CONTRIBUTING）。
- 界面文字只经 `Localized(...)` 或 SwiftUI 字面量；**裸中文不许进 Swift 源码**。
- 颜色、材质、圆角先在 `Design.swift` 的 `Palette` 里定义再引用；新色值不内联（`Spaces.swift` 那组空间色是既有例外，别再扩散）。
- 界面全在 main actor，语言模式钉在 Swift 5；别为一堆 `@Sendable` 仪式重排既有结构。
- 一个功能一个入口：设置项进 `Settings.swift` 的分区（`general / tabs / shortcuts / extensions / passwords / downloads / privacy / ai / about`），菜单项进 `App.swift` 的 `CommandMenu`，快捷键走菜单加 `KeyLayout`。

## 翻译约定

- 英文原文就是键；新增一句英文，同轮补 `Resources/zh-Hans.lproj/Localizable.strings` 的中文。缺了只回退英文（不崩），但中文界面漏句算没做完。
- 带值的句子写成 `Text(Localized("Search \(version) is downloading…"))`，键是骨架（`"Search {1} is downloading…"`）；中文可挪动、省略或重复 `{1}`。
- 同一概念全应用同一个词；沿用既有译法。
- 提交前 `plutil -lint Resources/*/Localizable.strings`。

## 文档与提交约定

- 提交信息中文（本 fork 自 `6295120` 起），一句讲因果，细节放正文。
- 文档**现状态写作**：正文写"是什么"，变更史归 `CHANGELOG.md` 与 commit。
- 一事一家：同一事实只有一个文件拥有，别处链接。
- **推送前看 remote**：`main` 跟踪 `origin`（上游 `driceroland/Search`），本 fork 叫 `aura` —— 推自己的改动用 `git push aura main`。

## 已知遗留（实测，别踩）

- **改名遗留**：`Tests/AddressRegression/run.sh`、`Tests/HistoryRegression/run.sh`、`Tests/DuskHarness.swift`、`Tests/popup_gesture_script.js`、`Tests/ExtensionWorkerRecovery/run.js` 仍写 `Sources/Search/…`，源码已在 `Sources/Aura/` —— 直接跑报 `No such file`。修脚本，**不要**建兼容目录。
- **引擎命名两套**：源码是 `Engine/aura-ai-engine.cpp`，`engine.sh` 产物是 `aura-ai-engine-<arch>`，运行时找的下载程序叫 `search-ai-engine`；以 `engine.sh` 与 `AIEngine.swift` 为准。
- `AI.shipped = false` 是 AI 附加功能的总闸（1.0.5 起收起）：动 AI 代码前先读这一行。
- **`swift test` 有 2 个既有失败**（2026-10-25 实测，218 例 / 64 秒）：`ExtensionWorkerPortTests.testRealShimEntryCoversContentScriptsAndExtensionPages`（shim 里 `__AURA_VERBOSE__` 未定义）、`SidebarPressTests.testOtherButtonsDoNotSelectOnPress`（右键也选中了）。全量验证看有没有新增，别去追这两个而不先问用户。
- 工作区常有其他会话未提交的活：提交前 `git status` 复核，只 `git add` 本轮文件。

## 维护本文件

每条规则 1-3 行并链接到它的家；细节与故事不搬进来。`CLAUDE.md` 是指向本文件的符号链接——编辑本文件，勿编辑链接。
