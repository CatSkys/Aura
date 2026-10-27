# 发版手册

从源码到「别人点开就能装」的全部动作，按顺序做一遍即可。只做发版的人读这一份就够；构建本身怎么实现的看 `build.sh` 的头注释。

三件事先说在前面，都是本 fork 的具体情况：

- **没有通行密钥权利**。`com.apple.developer.web-browser.public-key-credential` 要组织类型的开发者账号才能拿到（详见文末「为什么没有通行密钥」），Aura 是个人账号，所以构建里没有 `Aura.provisionprofile`。`build.sh` 的 ship 因此会拒发，发版时**必须**带上 `AURA_ALLOW_NO_PASSKEYS=1`。
- **签名身份**是 `Developer ID Application: HANGBIN JIN (49LSZKN27V)`，与 `Updater.team` 一致；换证书等于换团队，所有人收不到更新。
- **更新源**是 `https://catskys.github.io/Aura/appcast.json`（Intel 在 `/intel/`），由 `../aura-pages`（`gh-pages` 检出）提供。站点上是四件东西：`Aura.dmg`、`Aura.zip`、`appcast.json`、`appcast.json.zip`，每次发版由 `./publish.sh` 覆盖；`appcast.json` 里记着当前发布的版本。

## 一次性准备

逐项确认，缺哪项补哪项；括号里是 2026-10-27 的实测状态。

| # | 需要的东西 | 现状 | 怎么做 |
|---|---|---|---|
| 1 | Developer ID Application 证书 | ✅ 有（2031/07/14 到期） | 钥匙串里已有；`security find-identity -v -p codesigning` 能看到 |
| 2 | 公证凭据，keychain profile 名 `aura` | ✅ 有（0.1.0 两次公证 Accepted） | `xcrun notarytool store-credentials "aura"`（见下） |
| 3 | `../aura-pages` 检出（gh-pages） | ✅ 有，含 `appcast.json` 与 `intel/` | `git worktree add ../aura-pages gh-pages` |
| 4 | GitHub 仓库能发 Release | ✅ 有（`v0.1.0` 已发） | tag `v<版本>`，附 `Aura.dmg` 与由 `build/intel/Aura.dmg` 改名的 `Aura-Intel.dmg` |
| 5 | `python3` 与一次联网 | ✅ 有（0.1.0 的 DMG 由 dmgbuild 打出） | 首次 `release dmg` 会建 `.build/dmgbuild` 虚拟环境装 dmgbuild 1.6.7 |
| 6 | Apple 开发者协议 | ⚠️ 有待接受的 PLAA（**2026-10-29** 前） | 开发者门户顶部提示里接受，本人点 |
| 7 | 版本号 | `VERSION` 里是当前版本（发版时递增） | 规则见下：最后一位 +1，前两位由你定 |

### 公证凭据（唯一必须由你提供的凭据）

两条路，选一条。账号是个人还是组织都行，公证不看这个。

**A. App Store Connect API key（推荐，可撤可换）**

1. App Store Connect → 用户和访问 → 集成 → **App Store Connect API** → 生成密钥（访问权限「开发者」即可），记下 **Key ID** 与 **Issuer ID**，下载 `.p8`（只能下一次）。
2. 存进钥匙串：

```sh
xcrun notarytool store-credentials "aura" \
  --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer 00000000-0000-0000-0000-000000000000
```

**B. Apple ID + App 专用密码**

```sh
# appleid.apple.com → 登录与安全 → App 专用密码，生成一个
xcrun notarytool store-credentials "aura" \
  --apple-id "你的 Apple ID" \
  --team-id 49LSZKN27V \
  --password "abcd-efgh-ijkl-mnop"
```

存完自检：

```sh
xcrun notarytool history --keychain-profile aura     # 应列出（可为空）历史，而不是 "No Keychain password item found"
```

换名字用 `AURA_NOTARY_PROFILE=<名字>`；默认就是 `aura`。

### Homebrew（暂缓）

这一版不分发 Homebrew：tap 仓 `CatSkys/homebrew-tap` 还没建，`./tap.sh` 因此先不用。脚本本身已经能认 `cask "aura"`，等要上架时：在 GitHub 发一个 Release（tag `v<版本>`，附 `Aura.dmg` 与由 `build/intel/Aura.dmg` 改名的 `Aura-Intel.dmg`），再跑 `./tap.sh`。

## 每次发版

### 1. 定版与文案

**版本号规则**：每次发版只把**最后一位 +1** —— `0.1.0 → 0.1.1 → 0.1.2 …`；前两位（`0.1`）在换到下一个大阶段前不动，由你定。递增用这一行，别手写：

```sh
V=$(cat VERSION); echo "${V%.*}.$(( ${V##*.} + 1 ))" > VERSION; cat VERSION
```

**文案**：`NOTES.md` 与 `NOTES.zh-Hans.md` **各在文件最上面加一段**（一段话，别分多段）——

- 两段分别是同一版说明的英文与中文；第一段会进 appcast，显示在「设置 › 关于 › 更新」下面；
- 中文那份不是英文的逐句直译，按中文的节奏写；
- 口吻是**更新说明**：先一句说清这一版是什么，后面陈述式地讲它带来什么；
- 应用内「更新说明」页另有一处（`Sources/Aura/WhatsNew.swift` 的 `notes` 条目，`version:` 换成新版本号），英文句子同轮补 `Resources/zh-Hans.lproj/Localizable.strings`。

### 2. 构建并公证（Apple Silicon 与 Intel 各一次）

在**主仓**里做（产物只代表主仓 HEAD），主仓必须干净：

```sh
git status --porcelain        # 应为空

# Apple Silicon：构建 + DMG + ZIP + 公证 + 装钉 + appcast
AURA_ALLOW_NO_PASSKEYS=1 ./build.sh release ship

# Intel
AURA_ARCH=x86_64 AURA_ALLOW_NO_PASSKEYS=1 ./build.sh release ship
```

做完的产物：

```
build/Aura.dmg            build/Aura.zip            build/appcast.json            build/appcast.json.zip
build/intel/Aura.dmg      build/intel/Aura.zip      build/intel/appcast.json      build/intel/appcast.json.zip
```

`AURA_ALLOW_NO_PASSKEYS=1` 不是可选项：不带它，`ship` 会以「缺 `Aura.provisionprofile`」拒发——这是我们这个账号拿不到通行密钥权利的直接后果，不是错误。

### 3. 发版前核对（一条条过，不过就不发）

```sh
# 签名与权利
codesign -dv --verbose=2 build/Aura.app 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"
  # 期望：Developer ID Application: HANGBIN JIN (49LSZKN27V) / TeamIdentifier=49LSZKN27V / com.catskys.aura

# 二进制上没有通行密钥权利，这是预期的
codesign -d --entitlements :- build/Aura.app 2>/dev/null | grep -c "public-key-credential"   # 期望 0

# 公证票装钉在 DMG 上
xcrun stapler validate build/Aura.dmg build/intel/Aura.dmg          # 期望 "The validate action worked!"

# Gatekeeper 真的放行（相当于别人的 Mac 双击）
spctl -a -vvv -t install build/Aura.dmg                             # 期望 "accepted  source=Notarized Developer ID"

# ZIP 里的 app 也是签好的
ditto -x -k build/Aura.zip /tmp/zipcheck && codesign --verify --deep --strict /tmp/zipcheck/Aura.app; rm -rf /tmp/zipcheck

# appcast 与版本对得上，且签名可验（publish.sh 会再验一次）
python3 -c 'import json;d=json.load(open("build/appcast.json"));print(d["version"],d["build"],d["url"])'
```

公证被拒时看 Apple 的日志，别猜：

```sh
xcrun notarytool log <submission-id> --keychain-profile aura
```

`submission-id` 来自 `notarytool submit` 的输出，或 `xcrun notarytool history --keychain-profile aura`。

### 4. 发布到更新源

```sh
./publish.sh ../aura-pages                       # Apple Silicon → 站点根
AURA_ARCH=x86_64 ./publish.sh ../aura-pages      # Intel → 站点 intel/

git -C ../aura-pages add -A
git -C ../aura-pages commit -m "Aura <版本>"
git -C ../aura-pages push
```

`publish.sh` 自己会拦三种错：appcast 里的版本与 `VERSION` 不符、ZIP 里的二进制不是这个架构、签名 appcast 验不过（要求：`com.catskys.aura.appcast` + `49LSZKN27V`）。DMG 没公证它只提示不拦——**所以第 3 步别省**。

### 5. GitHub Release

更新靠的是第 4 步的 `aura-pages`；GitHub Release 是给人一个自己下载、也给发行留档的地方，仍然要做。

1. 在 `CatSkys/Aura` 发 Release：tag **`v<版本>`**（与 `VERSION` 一致，例如当前是 `v` + `cat VERSION`），标题写版本名。
2. 附上两个文件（名字要改准，Homebrew 以后按这个名字取）：
   - `Aura.dmg` —— `build/Aura.dmg`
   - `Aura-Intel.dmg` —— `build/intel/Aura.dmg` 改名
3. 说明写 `NOTES.md` 的第一段即可（与 appcast 里那句一致）。
4. 发完核对：Release 页上两个 DMG 都能下载，且下载回来的 `Aura.dmg` 的 sha256 与 `build/Aura.dmg` 一致：

```sh
curl -fsSL -o /tmp/Aura.dmg https://github.com/CatSkys/Aura/releases/download/v$(cat VERSION)/Aura.dmg
shasum -a 256 /tmp/Aura.dmg build/Aura.dmg     # 两个哈希应相同
xcrun stapler validate /tmp/Aura.dmg           # Release 上的这份也应带着公证票
rm -f /tmp/Aura.dmg
```

Homebrew 仍旧暂缓；等要上架时，`./tap.sh` 会从**这个** Release 取两个 DMG 算 sha256，所以名字别改。

### 6. 交付后自检

- 换台没装过的 Mac（或删掉本地 app 后）下载 DMG，双击 → 正常打开、**没有**「无法验证开发者」；
- 「设置 › 关于 › 更新」里读到新版本号与 `NOTES.md` 的第一段；
- Intel Mac（或 Rosetta 环境）从站点的 `intel/` 装 `Aura.dmg` 能用，GitHub Release 上的 `Aura-Intel.dmg` 也是同一份；
- GitHub Release 上的 `Aura.dmg` 与本地 `build/Aura.dmg` 哈希一致、并能通过 `stapler validate`。

## 回滚

- **更新源发错了**：`git -C ../aura-pages revert <commit>` 再 push；appcast 是纯文本，回滚即生效（已装在别人机器上的新版不会降级，但没人再被推上去）。
- **App 本身有问题**：GitHub Release 标为 Pre-release（或删掉 tag 与附件），再把 `appcast.json` 指回上一版；不要用同一个版本号重发（`Updater` 比的是 version + build 号）。
- **Homebrew（暂缓）**：tap 仓 `git revert` 那一个 `Aura <版本>` 提交，推送即可。

## 为什么没有通行密钥

`com.apple.developer.web-browser.public-key-credential` 是受限权利，Apple 的规则（Entitlements 文档 + Capability Requests 帮助页）要求**组织类型**开发者账号的 **Account Holder** 提交申请，批准后通过 managed capabilities 落到 App ID 上。论坛上 Akari（macOS Chromium 浏览器）的实测：个人账号提交后 support 回了「已签发」，但 App ID 里始终停在 Submitted、生成的 profile 也不含该权利。

所以本 fork 的构建不带 `Aura.passkeys.entitlements`：

- 站点上的通行密钥登录在这份构建里不可用（只能用密码/用户名，或去 Safari 用通行密钥）；
- Apple「密码」App 的账户也不可用（它同样要 `application-identifier` / `team-identifier` 这两项身份权利）；
- 哪天有了组织账号并获批，把 `Aura.provisionprofile` 放进仓库根目录、去掉 `AURA_ALLOW_NO_PASSKEYS=1` 即可，代码不用改（`Passkeys.swift` 已按 `ASAuthorizationWebBrowserPublicKeyCredentialManager` 实现）。

**注意钥匙串**：带权利与不带权利的构建，存的密码是分开的（签名身份与访问组不同）。一旦以后切到带 profile 的构建，用户要重新保存一遍密码；所以要么一直不带，要么一直带，别来回切。

## 与本项目无关但会被问到的

- **AI 附加功能**：`AI.shipped = true`（0.1.1 起随 app 发），所以设置里会有 Settings › AI 一页，默认关。引擎仍然不发：`AURA_AI_ENGINE_VERSION` 不设，`build.sh` 就不往 feed 里写 `ai` 字段，Aura 也就不提供「下到本机跑」那一项——本机跑模型靠用户自己的 Ollama 或 LM Studio。要开始发引擎：`./engine.sh arm64` 编好 `build/engine/aura-ai-engine-arm64`，发版时带上 `AURA_AI_ENGINE_VERSION=<比上一版大的整数>`，产物会落到 `build/ai/`，`publish.sh` 之外的这一步得手工把 `ai/` 也拷进站点。
- **图标**：用 Xcode 26 的 `actool` 打图时会有 "no Dark or Tinted style" 的提示，当前属于已知现象，不影响发版。
- **Intel 档**：`AURA_ARCH=x86_64` 的产物在 `build/intel/`，一切命令都加这个变量即可；两档的 appcast 各自独立。
