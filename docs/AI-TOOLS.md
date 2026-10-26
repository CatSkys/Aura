# AI 工具调用（tool use）方案

Aura 的 AI 现在只能「读一段页面文字，回一段文字」。这份文档是让它能真正动页面——开标签、点击、填表、翻页——的方案。

参考对象：`pi`（`@earendil-works/pi-agent-core@1.4.0`，`dist/agent-loop.js` 680 行）、`nanobrowser`（工具面与权限门禁）、Dia（`browser_use`，本机 `/Applications/Dia.app` 内的提示词与 schema）。不引入任何依赖。

---

## 1. 现状与缺口

### 已经有的（不用重写）

| 能力 | 位置 | 说明 |
|---|---|---|
| 真实鼠标点击 | `Bench.swift:540` `case "tap"` | `getBoundingClientRect` 取中心 → `NSEvent.mouseEvent` → `view.mouseDown/mouseUp`。**是真事件**，1Password 这类忽略合成事件的东西也认 |
| 元素定位 | `Bench.swift:4371` `Bench.locate` | selector → 中心坐标；支持 `text=登录` 按文字找 |
| 填表 | `Bench.swift:4395` `Bench.act` | 走原生 setter + 派发 `input`/`change`，React/Vue 收得到 |
| 提交表单 | 同上 `verb == "submit"` | `form.requestSubmit()` |
| 等待加载 | `Bench.swift:4215` `wait(for:until:)` | 轮询 `tab.loading` 到超时 |
| 开标签 | `Browser.swift:4681` `benchOpen` | `Browser.swift:4581` `open` |
| 读正文 | `AIPage.swift:350` `AIPage.script` | 正文抽取 + 可见性判定（隐藏/透明/0 字号/屏读专用/移出视口全部排除）+ 颜色可读性 |
| 截图 | `AIPage.swift:140` `AIPage.shot` | `takeSnapshot` → JPEG |
| 隔离世界 | `Tab.swift:15` `Web.world` | 页面看不见 Aura 的脚本 |
| 三家协议 | `AIClient.swift:143` `request` | OpenAI / Anthropic / Gemini 三种请求形状已手写，SSE 解析 `piece()` 三家都有 |
| 权限卡 | `Browser.swift:1389` `CaptureAsk` + `PageQuestions.swift` | 现成模板，还带反点击劫持（头半秒不收点击） |
| 文档换页回调 | `Tab.swift:338` `didCommit` | ref 失效的挂点 |
| 标签视图构建 | `Tab.swift:879` `build()` | 懒建，驱动标签前要先确保已建 |

### 真正缺的三样

1. **富消息**。`AIMessage` 只有 `role` + `text` + `images`，装不下 `tool_use` / `tool_result`。
2. **循环**。`Chat.swift:170` `go()` 是「一问 → 流式收完 → `finish()`」，没有「模型要工具 → 执行 → 回填 → 再问」。
3. **可交互元素清单**。`AIPage.script` 抽的是**正文**，不是**能点的东西**。这是全新的一块。

### 一个改不动的限制

`Engine/aura-ai-engine.cpp:203` 明确跳过任何 `content` 不是字符串的消息：

```cpp
if (!message.is_object() || !message.contains("content") || !message["content"].is_string()) continue;
```

而工具消息天生不是字符串。加上 1.7B 模型做 tool calling 不可靠，**v1 的工具能力只对云端 provider 开放**。本机引擎在 UI 上必须明说「不支持工具」，不能静默降级。

---

## 2. 从 pi 抄什么

### 2.1 消息分两型，只在调模型那一刻转换

pi 的 `AgentMessage` 和 LLM 的 `Message` 是两个类型，`convertToLlm` 每轮调一次（`agent-loop.js:265`）：

```js
const llmMessages = await config.convertToLlm(messages);
```

我们现在 `AIMessage` 直接就是 LLM 形状，`Chat.Line` 是 UI 形状，中间没有层。**接入工具前必须补这一层**，否则 tool_use/tool_result 会漏进存进 `chats.json` 的 Codable `Line` 里。

### 2.2 主循环是两层

```js
while (true) {                                    // 外层：等 follow-up
  while (hasMoreToolCalls || pending.length) {    // 内层：工具 + 插话
    message = await streamAssistantResponse(...)
    if (stopReason === "error" || "aborted") → 收摊返回，不重试
    toolCalls = message.content.filter(c => c.type === "toolCall")
    if (toolCalls.length > 0) {
      executed = message.stopReason === "length"
        ? failToolCallsFromTruncatedMessage(toolCalls)   // ★ 全部判失败
        : executeToolCalls(...)
      hasMoreToolCalls = !executed.terminate
    }
  }
}
```

**`stopReason === "length"` 那个分支要照抄。** 输出撞到 token 上限时，工具参数必然是被截断的 JSON，执行它等于执行一个半截指令——一律判失败，不执行。

### 2.3 单个工具调用是 8 步流水线

`prepareToolCall` → `executePreparedToolCall` → `finalizeExecutedToolCall`：

1. 按名字查工具 → 找不到**立即返回错误结果**，不抛
2. `prepareArguments` 兼容垫片（模型常把 `@` 带进路径参数）
3. **参数 schema 校验** → 不合法立即返回错误结果
4. **`beforeToolCall` → 返回 `{block: true, reason}` 就拦下**，变成一条错误 tool_result
5. 执行前后都查 `signal.aborted`
6. 执行中 throw → 转成错误结果
7. `afterToolCall` → 可改写 content / details / isError
8. **绝不 reject**

第 8 步是核心：**失败是给模型的输入，不是给调用方抛的异常**。模型看到错误才能自己纠正。第 4 步的钩子就是权限门禁的落点，不用另建一套机制。

我们在第 3 步和第 4 步之间再加两步，见 §3.6 与 §3.7：

3.5 **取 `say`** → 推到 `ChatPanel` 的脉冲行（给用户）
7.5 **收 `did`** → 写进 `tool_result`（给模型 + 当审计记录）

这两步不改 pi 的骨架，只是在正确的位置挂两个钩子。

### 2.4 两个细节

- `terminate` 只在**同一批每个结果都为 true** 时才中断（`shouldTerminateToolBatch`）。
- `replay?: "never" | "safe"`：为「副作用已发生但结果未知」的动作声明恢复策略。对应 Dia 提示词里 `?`（did not finish）那个标记。

### 2.5 pi 给不了的三样

| pi | 我们的情况 |
|---|---|
| `pi-ai` provider 抽象（22 依赖） | 不需要。`AIClient.request` 已手写三种形状 |
| `toToolDeclaration()` 一份声明转三家 | **要自己写** |
| `validateToolArguments()`（TypeBox） | **要自己写**，零依赖下不能引 JSON Schema 库 |

---

## 3. 工具面（v1，14 个）

一个工具 = 名字 + 描述 + 参数 schema + `execute` + 风险等级。

**除 `snapshot` / `read` / `screenshot` 这类纯观察外，每个动作另有两个必填字段**（`say` 见 §3.6，`did` 见 §3.7）：

- `say` — 模型写的，给用户看的一句
- `did` — 工具返回的，给模型看的一句

表中「参数」列省略这两个，不重复标注。

### 观察

| 工具 | 参数 | 实现 | 风险 |
|---|---|---|---|
| `snapshot` | `scope?`（ref，只看某个容器内）, `full?` | 新写 JS：遍历可见元素，发稳定 ref | 只读 |
| `read` | `ref?`, `format?` | 复用 `AIPage.script` | 只读 |
| `tabs` | `action`: list/open/select/close, `url?`, `id?` | `Browsers` / `Browser.open` / `close` | 只读 / close 需门禁 |
| `screenshot` | — | `AIPage.shot` | 只读 |

### 导航

| 工具 | 参数 | 实现 | 风险 |
|---|---|---|---|
| `navigate` | `url` | `tab.go(to:)`。**只收 http/https**，拒 `javascript:` / `file:` / `data:` | 低 |
| `back` / `forward` / `reload` | — | `PageSurface` 现成 | 低 |

### 动作

| 工具 | 参数 | 实现 | 风险 |
|---|---|---|---|
| `click` | `ref` 或 `x,y` | `Bench.locate` + `Bench.tap`（真实事件） | **需分类** |
| `set_value` | `ref`, `value`, `submit?` | `Bench.act` | **需分类** |
| `press` | `key`, `ref?` | `NSEvent` keyDown/keyUp | **需分类** |
| `scroll` | `direction`, `pages?`, `ref?` | `scrollBy` / `scrollIntoView` | 低 |

### 交互

| 工具 | 参数 | 实现 | 风险 |
|---|---|---|---|
| `wait_for` | `ref?`, `text?`, `state?`, `timeoutMs?` | Swift 侧轮询 `evaluateJavaScript`，**不在页面里挂 setTimeout** | 低 |
| `ask_user` | `reason`, `title` | 原生确认卡，交还用户 | 只读 |

### 不进 v1

- `evaluate(js)` —— 等于把任意代码执行交给模型。页面里的注入文本能直接变成任意脚本。
- `upload_file` —— 要 `NSOpenPanel`，权限面太大。
- 批量 `fill_form` —— 一次提交多个字段，风险叠加且难以逐步确认。

### ref 的语义（照抄 Dia / nanobrowser）

- `[12]` 编号可操作元素；**一旦发出，在元素存在期间不变**
- **永不复用**同一个编号
- **页面换文档即全部失效** —— 挂 `Tab.didCommit()`（`Tab.swift:338`）
- 模型拿旧 ref 调用 → 明确报错 `ref 12 已失效，请重新 snapshot`，**不要猜**

### 3.6 每个动作带一句摘要

**每个动作都必须带 `say`：给用户看的一句话，说它正在做什么。** 硬要求，不是可选项。

理由：用户不需要看逐步的处理清单，但需要一眼知道「现在这一下是在干什么」。一句话够了，列表是负担。

（这一节就是 §2.3 流水线里补的 3.5 取 `say`；收 `did` 见 §3.7。）

#### 两家怎么做，差在哪

这块 `browser-use` 和 Dia 是两套不同的做法，取舍很关键：

| | browser-use | Dia |
|---|---|---|
| 字段 | `ActionResult.long_term_memory` | `activity` |
| 位置 | **动作的返回值** | **动作的入参** |
| 谁写 | **工具自己生成** | **模型自己写** |
| 粒度 | 每个动作 | 每次调用 |
| 目的 | 喂给下一步的模型 | 喂给用户 |

browser-use 的 `long_term_memory` 是**工具实现里拼出来的**，不是模型给的。`click` 这么拼（`tools/service.py:752` + `tools/utils.py:6`）：

```python
element_desc = get_click_description(node)
memory = f'Clicked {element_desc}'
memory += await _detect_new_tab_opened(browser_session, tabs_before)
```

`get_click_description` 拼的是 `tag + type + role + checkbox-state + "短文本" + id/name/aria-label`，实打实从 DOM 读出来的。所以它准确（不会撒谎），但**是机器的腔调**：`Clicked button "加入购物车"`。它的用途也确实是喂模型——`message_manager/service.py:335` 把它拼进下一步的 `action_results`。

Dia 的 `activity` 是模型写的，规则是：

> Short user-facing description of the task phase this call performs, such as **Picking dates** or **Selecting invitees**. Use present tense, at most 80 characters, and no reasoning or claims of completion.

写给用户看，所以是人的腔调（`Picking dates` 而不是 `Clicked radio`），代价是**模型可能写歪**——这也是 Dia 为什么要额外注明「no reasoning or claims of completion」。

#### 我们的做法：两者都要，各归各位

这两件事被 browser-use 和 Dia 分别解决了一半，我们两个都要：

| 字段 | 谁写 | 给谁 | 用途 |
|---|---|---|---|
| `say` | **模型** | **用户** | 输入框上方那一行脉冲 |
| `did` | **工具自己** | **模型** | 进 `tool_result`，成为下一步的依据 |

**分成两个字段，是因为它们服务于不同的人。** 合成一个必然顾此失彼：给用户看的要像人话，给模型看的要准确到能据以决策。

`say` 从 Dia 抄规则：动词开头、现在进行时、说做了什么不说要达成什么、用界面上的词、理想 12 个汉字上限 40、不许宣称结果。

`did` 从 browser-use 抄做法：工具在 `execute` 返回时顺手拼一句，**如实描述发生了什么**，包括 browser-use 那个很实用的小机关——点击后检测是否开了新标签：

```
did: 点击了 button「加入购物车」（在新标签中打开）
```

`did` 不光是给模型看的，它还是**审计记录**。用户问「你刚才到底点了什么」，答案在这里，而不是模型自述的 `say`。

#### 显示位置

`ChatPanel` 已有「Thinking… / Reading this page…」的文字脉冲（`ChatPanel.swift:201`，`calm` / `faint`）。`say` 就用同一处、同一个语法：

```
正在填写收货地址…
```

动作结束换下一句，整轮结束就消失，**不留历史**。要回看做了什么，去页面自己的历史，不在对话里堆。

`Chat.Line` 因此只加一个 `@Published var saying: String?`（当前这一句），不存动作序列。

#### 另一个值得抄的：动手时高亮那个元素

browser-use 每次交互前会**在页面上把要动的元素闪一下**（`browser/session.py:2982` `highlight_interaction_element`，颜色和时长可配，自动淡出，失败静默）。

这比任何文字都直观：用户眼睛在页面上，看见一个框亮起来，就知道 AI 在动哪儿。而且它顺手解决了「AI 偷偷点了什么」的恐惧——**高亮是给用户看的，不是给模型看的**。

我们实现起来比它简单得多：`executeJavaScript` 给元素加一个短暂的 outline 样式，`setTimeout` 撤掉。用 Aura 自己的世界（`Web.world`），页面看不见这个脚本。只在 `prefs.aiToolsReveal`（默认开）时做，并且**绝不因高亮失败而让动作失败**——照抄它 `suppress_exceptions=True` 的取舍。

#### 校验

`say` 在 schema 里是每个动作的 `required` 字段。模型不给 → 参数校验失败 → 按 pi 的规矩变成一条 `isError` 结果回给它，**不替它编**。

`did` 反过来：**工具必须给，给不出就是实现有 bug**。它是我们自己的契约，不依赖模型。

#### 一个例外

`ask_user` 的标题就是它的 `say`（「登录后才能查看库存」），不另给。

### 3.7 各工具的 `did` 怎么写

`did` 是工具的实现细节，但格式要统一：**动词 + 对象 + 结果**，括号里放需要模型知道但不该占主句的信息。

| 工具 | `did` |
|---|---|
| `click` | `点击了 button「加入购物车」` / `点击了 button「加入购物车」（在新标签中打开）` |
| `set_value` | `填写了 textbox「邮箱」为 person@example.com` / 密码框只写 `填写了 password「密码」`，**绝不回显值** |
| `press` | `按了 Enter` / `在 textbox「搜索」里按了 Enter（提交了表单）` |
| `scroll` | `向下滚动了两屏` / `滚动到 link「退款政策」` |
| `navigate` | `打开了 https://example.com/pricing（200）` |
| `tabs` | `新开了标签：示例网 - 定价` / `切到标签「收件箱」` |
| `snapshot` | 不给 `did`（内容本身就是结果） |

三条规矩：

1. **不回显敏感值**。密码、卡号、验证码，`did` 里只有字段名，没有值——因为这个字符串会进 `tool_result` 发给 provider。
2. **不宣称结果**。「点击了提交按钮」对，「已成功下单」错——后者是 `finishTurn` 之后才能判断的事。
3. **变化要说**。新标签、表单被提交、页面跳转，这些是模型下一步最需要知道的事，browser-use 的 `_detect_new_tab_opened` 就是干这个的。

---

## 4. 安全

### 4.1 现有安全论证会失效

`AIPage.swift:18` 那段是整个 AI 功能的安全基石：

> What does is that the model can't do anything — it only answers, in plain text.

接上工具，这句话不成立了。页面里的提示注入从「让答案跑偏」升级成「让浏览器真的去点」。这道坎不是技术问题，是必须重新论证一遍的问题。

### 4.2 五条硬约束

1. **独立开关**。不跟 `prefs.ai` 绑，单独一个 `ai.tools`，默认关。总闸 `AI.shipped` 继续管着。
2. **观测内容只进 `tool_result`，绝不进 system**。页面文字是数据不是指令。
3. **`navigate` 白名单**：只收 http/https。拒 `javascript:` / `file:` / `data:` / `blob:`。
4. **禁止模型把页面里读到的地址当可信跳转目标**。Dia 的规则是「URL 必须来自上下文，不许编造」，同理可用。
5. **登录 / 验证码 / 支付信息绝不让模型填**。只能 `ask_user` 交还用户。Dia 明确要求「不要在聊天里索要密码」。

### 4.3 四类动作强制确认

抄 nanobrowser 的分类器思路，**词表宁可多不可少**（误报只多一次弹窗，漏报是不可逆动作）：

| 类 | 触发词 | 例子 |
|---|---|---|
| `pay` | pay / buy / checkout / purchase / 下单 / 付款 / 支付 / 转账 / 订阅 | 「立即购买」 |
| `delete` | delete / remove / unsubscribe / 删除 / 清空 / 注销 | 「删除账号」 |
| `submit` | submit / send / publish / post / confirm / 提交 / 发送 / 发布 / 保存 | 「发布评论」 |
| `grant` | authorize / allow access / 授权，尤其在 `/oauth\|authorize\|consent` 路径 | 第三方授权 |

判定看三样：元素的可访问名字、它所在的表单、当前地址的路径。

**Enter 在无 form 的输入框里发出内容也算 `submit`** —— 聊天框和评论框都是这样。

### 4.4 确认卡

复用 `CaptureAsk` 的形状（`Browser.swift:1389`）+ `PageQuestions.swift` 的画法：

- 标题说清要做什么：「提交这张表单？」
- 列出会被改动的字段与目标站点
- 三个答案：允许一次 / 这个站点总是允许 / 不接受
- **头半秒不收点击**（照抄 `CaptureAsk.shown` 的反点击劫持）
- 记住的粒度是**站点 + 动作类**，不是单个按钮

---

## 5. 快照

### 5.1 WKWebView 没有公开的可访问性树

这是必须承认的限制。Dia 用 Chromium 的 a11y 树，我们只能用 DOM 近似：`tagName` + `role` 属性 + `tabindex` + `contenteditable` + 事件监听器有无。

**做不到 Dia 那个质量**，要接受更粗糙的快照。

### 5.2 但 `AIPage.script` 的可见性判定可以复用

`AIPage.swift:380` 那段 `shown()` 已经解决了最难的部分：

```js
if (parseFloat(s.fontSize) < 6) return false;              // 太小
if (s.clip && s.clip.indexOf('rect(0') === 0) return false; // 屏读专用
if (parseFloat(s.textIndent) < -500) return false;          // 推到左边
if (r.width < 1 && r.height < 1) return false;             // 零尺寸
```

快照脚本直接复用这套判定，只换挑选目标：从「文字节点」换成「可交互元素」。

### 5.3 格式

缩进大纲，一行一个元素（照抄 Dia / stagehand）：

```
[12] button "加入购物车"
[13] textbox "邮箱" = person@example.com
[14] link "忘记密码"
  [15] link "用手机号登录"
[16] checkbox "记住我" ✓
```

末尾必须注明省略了什么：

```
（视口上下各一屏内的 47 个元素；另有 12 个在视口外）
```

### 5.4 只有变化时给变化

Dia 的做法：首次快照给全量，之后只给 `+` 新增 / `~` 修改 / 消失列表。省 token，也让模型注意到页面真的动了。

v1 可以先只做全量，把差异留到 v2 —— 但**「No changes」这个信号值得早做**，它能避免模型在没变的时候瞎点。

---

## 6. 落地的文件

```
Sources/Aura/
  AITool.swift       一条工具的定义 + 14 个工具的实现
  AIToolLoop.swift   两层循环 + 8 步流水线 + 事件流
  AIToolSnap.swift   快照脚本（复用 AIPage 的可见性判定）+ ref 注册表
  AIToolRisk.swift   动作分类 + 确认卡
  AIToolReveal.swift 动手前在页面上闪一下那个元素（§3.6）
  AIToolWires.swift  一份工具声明 → 三家 provider 的形状（可并入 AIClient）
```

`say` / `did` 不单独开文件：`say` 是 `AITool` 定义里的一个字段，`did` 是 `execute` 的返回值的一部分（`AIToolResult { did, content, isError }`）。

### 改动点（按波及面从小到大）

1. **`AIMessage` 加 content block**。保留纯文本路径不变，本机引擎那头一行不动。
2. **`AIClient.request` 三个 wire 分支各加一份 tool 序列化**。
3. **`Chat.go()`** 从「一次流式收完」改成「跑 loop」，`Chat.Line` 加一个 `saying: String?`（§3.6）。
4. **`ChatPanel`** 把 `saying` 接到已有的脉冲行（`ChatPanel.swift:201`）。
5. **`Tab.didCommit()`** 加一行 `AIToolSnap.invalidate(tab)`。
6. **`Bench.swift`** —— **这是最大的一处**。真实点击/填表/等待现在都被 `Store.testing` 挡着：
   ```swift
   guard Store.testing else { answer(["error": "tap only works on a --test run"]); return }
   ```
   要把「机械动作」从「bench 协议」里抽出来，成一组不依赖 `Store.testing`、不依赖 Unix socket 的纯函数，bench 和 AI 工具共用一份。**不是复制代码**——复制会让两边的真实点击行为漂移。

---

## 7. 分四步落地

### 第一步：循环骨架（不碰页面）

- `AIMessage` 加 content block
- `AIToolLoop` 的两层循环 + 8 步流水线（含 3.5 取 `say`、7.5 收 `did` 两个挂点）
- 两个假工具（`echo`、`now`）跑通「模型要工具 → 结果回填 → 再问」
- 三家 provider 的 tool 序列化 + 解析
- `Chat.Line.saying` + `ChatPanel` 的脉冲行接上 ← **这一步就把 `say` 跑通**，不必等到有真工具

**验收**：`./bench ai` 能跑一个多轮 tool loop，输入框上方能看到 `say` 在换；本机引擎那侧完全不受影响。

### 第二步：只读工具

- `AIToolSnap`：快照脚本（复用 `AIPage.shown()` 的判定）
- `snapshot` / `read` / `tabs` / `screenshot`
- ref 注册表 + `didCommit` 失效

**验收**：打开一个真实页面，模型能说出「页面上有个叫 X 的按钮，在第 12 号」。

### 第三步：导航与动作

- 抽出 `Bench` 的机械动作层
- `navigate` / `back` / `forward` / `reload`
- `click` / `set_value` / `press` / `scroll` / `wait_for`
- 每个动作写出它的 `did`（§3.7 的措辞表）
- `AIToolReveal`：动手前闪一下那个元素
- **先不加门禁**，在测试世界里验证动作真的生效（用 `./bench` 对照）

**验收**：模型能在一个测试页面上填表并提交；用户能看见元素被高亮闪一下。

### 第四步：门禁与 `ask_user`

- `AIToolRisk` 分类器
- `beforeToolCall` 钩子接入确认卡
- `ask_user` 工具
- 独立开关 `ai.tools` + Settings 里的一行说明

**验收**：点「立即购买」必须弹卡；`navigate` 传 `javascript:` 必须被拒。

---

## 8. 必须先回答的问题

1. **`AI.shipped` 到底是 true 还是 false？** `AGENTS.md` 的「已知遗留」写 `AI.shipped = false`，但 `Sources/Aura/AI.swift:26` 实际是 `static let shipped = true`。文档和代码不一致，工具功能跟不跟这个闸取决于哪个是对的。

2. **粗糙的快照能不能接受？** 没有 a11y 树，`snapshot` 只能给 DOM 近似。Dia 的质量我们达不到。要不要为此降低第一版的野心（比如只支持「按文字找元素」，不给编号）？

3. **确认卡的记忆粒度**。「这个站点总是允许」会不会太宽？Dia 每次都要问，nanobrowser 按动作类记。我倾向**站点 + 动作类**，但这是产品决定。

4. **工具调用的可见性**。模型点了 5 个按钮，用户要看到什么？Dia 是「✓ 完成 / ✗ 失败 / ? 未完成 / - 未执行」的逐步列表。我们要不要在对话里也画一份？还是只在动作发生时让页面自己动？

---

## 9. 落地记录（实现后回填）

上面的方案是按设计写的；这一节记实际情况，凡与上文冲突，以本节为准。

### 文件比方案多三个

| 方案 | 实际 | 为什么 |
|---|---|---|
| — | `PageAct.swift` | 方案 §6 第 6 条要的「机械动作层」。`Bench` 的真点击/填表/按键改成调它，于是探针按的和助手按的是同一段代码 |
| — | `AIToolArguments.swift` | 一份工具参数的类型与校验，独立出来才有单测 |
| — | `AIToolAsk.swift` | 确认卡与 `ask_user` 的面板；`AIToolRisk` 只管分类，不管界面 |
| — | `BenchTools.swift` | `./bench ai tools …` 的协议层，属于探针不属于产品 |

### `did` 的形状改了

方案 §2.3 说 `did`「进 `tool_result`」，`AIToolResult { did, content, isError }` 是三件并列的东西。落地时先照字面做了，结果 `did` 是个死字段：既没进 `content`（模型看不到），界面也不显示它（`Chat` 收到 `.did` 事件只是清掉 `saying`）。

现在 `did` **就是 `content` 的第一行**：`Result.ok(_ did: String, detail: String = "")` 把它拼在 `detail` 前面。于是模型第一步读到的就是那句记录，用户问「你刚才到底点了什么」，模型引用的也是同一句——不会出现「记录」和「模型读到的」两套说法。

顺带解决了另一件事：方案里 `did` 的示例是中文（`点击了 button「加入购物车」`），但它是发给 **provider** 的文本，而 `did` 又会被模型转述给用户。改成英文之后，源码里不再有 18 条裸中文字符串（AGENTS.md 明令禁止），也不需要为它们进译文表。

### `Store.testing` 的处理

方案 §6 第 6 条说要把它从机械动作里拿掉。实际是：`PageAct` 是纯函数、不带任何闸；`Bench` 保留它自己的 `Store.testing` 判断（那是探针的门），AI 工具走 `PageAct`，两个门各自独立、互不影响。

### `say` 只在脉冲行

方案 §8 第 4 个问题问「要不要在对话里也画一份逐步列表」，落地取的是**不画**：只有输入框上方那行脉冲显示 `say`，动作本身靠页面上闪一下框来体现（`AIToolReveal`）。对话里不留动作历史。

### §8 四个问题的实际答案

1. **`AI.shipped`** —— 以代码为准：`Sources/Aura/AI.swift:26` 是 `true`。它是总闸，`ai.tools` 是它下面另一个默认关的开关。
2. **粗糙快照** —— 接受。编号 + 缩进 + `role "name"`，够模型定位；没有 a11y 树做不到 Dia 的质量，这一版不为它降野心。
3. **确认卡粒度** —— 站点 + 动作类（`.pay` 除外，花钱每次都问）。分类器故意过度触发。
4. **可见性** —— 见上：只有脉冲行 + 元素闪框。

### 一个只有端到端才看得出的 bug

`AIToolLoop.run` 最初把这一轮的消息只累进**返回值**，没累进 `history`。于是每一轮都拿最初那两句去问模型，它永远看不到自己上一次的工具结果——单测全绿（每个工具本身都对），整轮全坏。`Tests/AuraTests/AIToolLoopTests.swift` 用一个本机 SSE 假 provider 钉住它，并且回退修复后确实会红。
