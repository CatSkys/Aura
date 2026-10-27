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
# 构建 —— release 约 200 秒（整模块重编，改一行也一样），自证别用它
./build.sh                                # 交付产物 build/Aura.app；只在要给人看时跑
AURA_OUT=build/debug ./build.sh debug     # 调试档，秒级；产物在 build/debug，不碰交付产物
AURA_ARCH=x86_64 ./build.sh release dmg   # Intel 档，出 build/intel/
./build.sh release dmg | ship             # + DMG/ZIP/appcast；ship 再公证装钉

# 快速腿 —— 默认这条：文案、译文、注释、文档、脚本、样式微调
./check.sh                                # 编译＋零新增警告＋译文表语法＋缺口计数，秒级

# 窄腿 —— 梯子，从便宜的一端上：changed → 套件 → 逻辑腿 → all
./test.sh changed                         # 按这次改的文件挑套件，约 2-10 秒
./test.sh ExtensionWorkerPortTests        # 一个套件，约 2 秒
./test.sh                                 # 逻辑腿：10 个重套件之外的 400 例，约 21 秒
./test.sh heavy                           # 只有那 10 个重套件，约 214 秒
./test.sh all                             # 全量 492 例，约 243 秒；交付前跑这条，一轮只跑一次
./test.sh --list                          # 这套是怎么分的

# 全量 —— 只在跨模块、动契约、交付前才跑（就是 ./test.sh all）
# 492 例 / 约 243 秒，其中 88% 是 10 个套件：ApplePasswords 85s＋ApplePairing 21s
# （Debug 档的真 SRP-3072 模幂，release 档只要 2 秒）、PinDrag 23s、SidebarPress 23s、
# DownloadLifecycle 14s、TabCapture 13s、HostPipe 13s、TabShortcutHint 8s、
# Shield 7s、ScreenPermission 7s

# 界面行为 —— 只跑受影响的那个探针
python3 Tests/<名字>.py                   # 对 build/Aura.app；先 ./build.sh
AURA_APP=build/debug/Aura.app python3 Tests/<名字>.py
                                          # 对调试档：省掉一次 release 构建，
                                          # 改界面时默认用这条
./Tests/AddressRegression/run.sh          # 解析类回归（swiftc 单编，秒级）
./Tests/HistoryRegression/run.sh          # 历史条目的身份

# 交付：合并 → 需要时构建 → 清场
./deliver.sh <slug> [--wait 600]           # 一棵树
./deliver.sh --ready [--wait 600]          # 把能合的都合了：一次窗口、一次构建
./deliver.sh --status                      # 锁在谁手里、待交付、产物覆盖没覆盖 HEAD

# 测试世界与探针
./fresh.sh | ./fresh.sh again             # 测试世界；没有 build/Aura.app 时建 debug 档
                                          # （release 那档是两分钟，探针不需要）；
                                          # AURA_APP=<另一个 app> 也能指；AURA_PROBE=<slug> 一树一世界
./bench help                              # 驱动运行中的 app；改界面一律加 --test 或 --world

# 译文
./Tools/i18n.py scan | missing | check
plutil -lint Resources/*/Localizable.strings

# 并行与提交
./tree.sh <session> [task]                # 会话树：一单一个分支，.build 留热
git worktree add ../Aura-<slug> -b feat/<slug>   # 一次性任务也可以单独开树
git worktree remove ../Aura-<slug>        # 收尾再 git branch -d feat/<slug>
./guard.sh                                # 主仓有未提交的 app 改动就拒绝编译
./hooks.sh [on|off]                       # 机械卡点：主仓拒收直接提交、拒收不是 deliver.sh 的合并
gitleaks git --pre-commit --staged        # 提交前扫密钥（.gitleaks.toml）

# 发版与外部动作 —— 只在用户明确要求时
./engine.sh [arm64|x86_64]                # AI 引擎（llama.cpp 固定 commit，static，沙盒签名）
./ideas [md]                              # 维护 ROADMAP（写回 officecommun 的库）
./publish.sh ../aura-pages                # 三个文件放进 Pages worktree
./tap.sh                                  # 写进 Homebrew tap
```

## 完成的定义：快速 → 全量 → 交付

- **默认 `./check.sh`，别默认全量**：文案、译文、注释、文档、脚本、样式微调，编译通过加零新增警告就够（秒级）。全量是最贵的动作，不是稳妥的选择。
- **什么才算行为改动**：`Sources/Aura` 里除注释与文案字面量之外的改动、`Resources/Shield` 的生成物、`Engine/`、`Package.swift`。这时走梯子：`./test.sh changed`（改到 `X.swift` 而 `Tests/AuraTests/XTests.swift` 在，就只跑它；挑不出来它自己退回逻辑腿）→ 绿了再往上加一格 → 跨模块、动契约、交付前才 `./test.sh all`。
- **全量一轮只跑一次，而且放在最后**：红了要修的是那个套件（`./test.sh <套件>`，2 秒），把全量再跑一遍只为找错误输出是最后的手段。有一轮会话在同一份代码上跑了四次全量，93 分钟里光这一项占 11 分钟。`./test.sh all` 替你记着这条：上一次全量绿了、之后 `Sources/`/`Tests/` 没动过，它跳过并说明白（真要再跑：`--again`）。
- **后台等全量的时候别空转**：等的四五分钟拿去做别的（注释、`CHANGELOG`、下一个问题的取证），或者干脆放到交付前最后一步。
- **一轮改动的三种腿，量过的**：文案/注释/译文 `./check.sh` ≈2 秒；逻辑 `./test.sh` ≈21 秒；界面 `AURA_OUT=build/debug ./build.sh debug`（改一行约 20-38 秒）＋ `AURA_APP=build/debug/Aura.app python3 Tests/<名字>.py`（一个探针 16-25 秒）≈40-50 秒。30 秒的量级到逻辑腿为止，界面那一腿省不掉探针自己的十几秒。
- **自证不跑 release**：`./build.sh` 是一次整模块的 release 编译（~200 秒，改一行也一样）。自证用 `swift build`，要看界面就 `AURA_OUT=build/debug ./build.sh debug`（探针加 `--app build/debug/Aura.app`）；release 只在交付、或用户要看时构建一次。
- **测试纪律**：一条命令一次跑完；同一轮最多重跑两次，仍红就带着输出停下报告；探针先确认世界在答（`./bench --test tabs`）再等它。
- **自证在测试世界，验收归用户**：世界由启动方式决定（`AURA_PROBE` 有值或可执行文件在 `/.build/` 下＝测试世界；`build/Aura.app` 不带变量＝真身）。改界面、装扩展、窗口尺寸、真键盘事件一律 `--test`/`--world`；不自行截图当验收、不擅自换 `/Applications/Aura.app`。
- **交付**：`./deliver.sh <slug>`。只改文档/脚本（不碰 `Sources/`、`Resources/`、`Engine/`、`Package.swift`、`VERSION`）就不重建产物；主仓有别处的活时也不重建。产物只代表主仓 HEAD。
- 改变行为的改动同轮补 `CHANGELOG.md` 的 `Unreleased`；`NOTES.md` 只在发版时写（第一段进 appcast）。
- 提交信息中文，一句讲清因果；临时探针、`AURA_MEASURE`、临时 `defaults` 当轮撤干净。

## 并行任务：一棵树一个世界

- **一个会话一棵树，一单一个分支**：`./tree.sh <session>` 建树、`./tree.sh <session> <task>` 换分支——`.build` 留热，第二单起编译是秒级（新树每次从零：debug 44 秒、测试再一分钟）。树名只按会话区分，隔离照样有。
- **主仓不承接活，但别让分支攒着**：活全在树里。主仓被别的会话占着时，`./deliver.sh` 允许**文件不重叠**的合并先落地（重叠就拒），这次不构建——产物会把那份活编进去。**不许替别人 stash**（教训：为合 `feat/facade` 把 15 个文件的活收起来四分钟，那次构建的产物因此不含那份活）。索引里有 staged 改动时 `git merge` 一律拒收，先让它 unstage。
- **主仓不许攒活，这条是机械卡住的**：`./guard.sh` 在主仓检出里发现 `Sources/`、`Resources/`、`Engine/`、`Package.swift`、`VERSION` 有未提交改动就拒绝编译，`./check.sh` 与 `./build.sh` 开头都调它——想直接在主仓改再编译，第一步就被打回，去 `./tree.sh` 开树。**也不许在主仓 `git reset --hard` / `git checkout -- .` / `git clean`**：那会连别人四个小时的活一起清掉，清场只有 `./deliver.sh` 做完的那一次。
- **一棵树一个测试世界**：`./fresh.sh` 与 `./bench --test` 用固定的 `test` 世界，两棵树同时用会抢同一个 socket；并行时 `AURA_PROBE=<slug> ./fresh.sh` 配 `./bench --world <slug>`。`Tests/*.py` 按检出路径自己分世界，不用管。
- **`../aura-pages` 不是任务树**：那是 `gh-pages` 的检出，`publish.sh` 认这个路径。
- **新树的 `.build/` 是冷的**：第一次 `swift build` 从头编译，属正常；别在两棵树间共享构建目录。

## 并行交付：一次只合一个

- **合并在锁上排队，排队是脚本的事**：`./deliver.sh <slug>` 抢 `.git/deliver.lock`（所有树共享一把）；第二个**自己等**（默认 300 秒，`--wait 600` 等更久），每 10 秒说一次谁在跑。**不要用 `sleep` 轮询交付**——一轮 30 分钟的体检里大半时间都花在这种轮询上。
- **锁的进程死了就被接管**：`who` 里记着 pid，拿锁的进程已经不在了就当场接管（被杀的交付不该把所有人都挡住）；确认没在跑才手工 `rm -rf .git/deliver.lock`。
- **主仓的合并只有 deliver.sh 能发起**：`.git-hooks/pre-merge-commit` 认两样——`AURA_DELIVER=1`（`deliver.sh` 自己 export），或者顺着这次合并的进程祖先找到正好是 `.git/deliver.lock/who` 里那个 pid（也就是拿着锁的那个 `deliver.sh`）。别的 `git merge` 在主仓一律被拒：手打合并绕过了锁和 `merge-tree` 预演，两个会话同时合就是互相盖。**被拒时它已经把合并写进工作区了**，照它说的 `git merge --abort` 退回去（钩子替不了这一步：git 跑钩子时握着索引锁）；真要手动合（合上游之后）：`git merge --no-verify <ref>`。
- **冲突在树里解决**：`git -C ../Aura-<slug> merge main`，在树里解冲突、构建、验证，再交付。`deliver.sh` 用 `git merge-tree` 预演，会冲突就直接拒——主仓永远不出现要人工解的合并。
- **能合就一次合完**：`./deliver.sh --ready` 把当前所有"树干净、与 main 不冲突、不撞主仓 WIP"的分支在一个锁窗口里合掉，然后**只构建一次**、只清一次场。三个任务从 ~600 秒降到 ~200 秒。
- **产物戳决定要不要重建**：`.git/artifact` 记着 `build/` 是哪个提交构建的；自那以后没有 `Sources/`、`Resources/`、`Engine/`、`Package.swift`、`VERSION` 的改动就不重建（实测跳过时整次交付 0.6 秒）。`./deliver.sh --status` 直接告诉你覆盖没覆盖 HEAD。
- **`CHANGELOG.md` 走 union 合并**（`.gitattributes`）：两条任务在同一天、同一处加一行是常态，union 把两行都留下，不为这一处互相挡；别的文件没有这个待遇。
- **构建失败就撤回合并，撤回不碰别人的活**：先用 `git reset --keep`——合并期间别的会话往工作区写的东西，它一概保住（真冲突就拒绝撤回）；被拒绝时才把这些改动存进 `.git/parked/<时间>/`（跟踪文件存成 git 对象、未跟踪文件原样复制），把 `git stash apply <sha>` 交回来，再硬撤。**没有一份活会静默消失**（教训：会话说自己的 SideBand 改动被交付清了，从此工作区在撤回路径上必须可恢复）。清场失败（树里又长出新东西）一样停下，绝不 `--force`。
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

- **`Tests/ExtensionWorkerRecovery/live.py` 还没真跑过一次**：它钉死的 `Search.app` 与进程名已收成 `APP_NAME = 'Aura'`、`--self-test` 56 条全过，但一次真跑要拉起 app 与 lldb（上限 504 秒）——这是唯一覆盖「真 WebKit worker 卸载/重载到真端口」的东西，改名之后值得跑一次把结论落下来。
- **`Tests/popup_gesture_script.js` 没人跑了**：它读 `PopupGesture.swift` 的源码做文本检查，路径已修，但仓库里没有任何脚本或套件调用它——要么接进一个跑器，要么删掉。
- **引擎命名两套**：源码是 `Engine/aura-ai-engine.cpp`，`engine.sh` 产物是 `aura-ai-engine-<arch>`，运行时找的下载程序叫 `search-ai-engine`；以 `engine.sh` 与 `AIEngine.swift` 为准。
- `AI.shipped = true` 是 AI 附加功能的总闸（0.1.1 起随 app 发，各项开关默认关）：动 AI 代码前先读这一行。引擎仍不发（`AURA_AI_ENGINE_VERSION` 不设），本机模型靠用户的 Ollama 或 LM Studio。
- **译文表有既有缺口**（2026-10-25：662/707，缺 45、未用 282）：`./Tools/i18n.py check` 因此恒红，当诊断用，不当门槛；`./check.sh` 只报数字。
- **测试世界里认按钮的用例必须走事件队列**：`window.sendEvent` 不设 `NSApp.currentEvent`，于是 `MiddleClick` 与菜单都"看不见"是哪个键，右键也会落到 SwiftUI 的按压手势上——`SidebarPressTests` 为此留了 `sendQueued`（`NSApp.postEvent` + 关键窗口）。用直接派发去断言按钮相关的行为，得到的是假信号。
- 工作区常有其他会话未提交的活：提交前 `git status` 复核，只 `git add` 本轮文件。

## 维护本文件

每条规则 1-3 行并链接到它的家；细节与故事不搬进来。`CLAUDE.md` 是指向本文件的符号链接——编辑本文件，勿编辑链接。
