# MC_SpawnMenu — 我的世界创造背包风格的 Q 菜单

MCHUD 的配套模块。按 **Q** 不再打开 GMod 自带的生成菜单，而是弹出一个
**Minecraft 创造模式背包**风格的格子窗口，里面是服务器上所有可生成的武器。
鼠标悬停看名字，点一下就把武器给到你手上 —— 就像在 MC 创造模式里拿东西。

> 用 `preview.html` 可以先看个大概样子（在浏览器里打开）。

---

## ⚠️ 先看这条（重要）

MCHUD 本体的卖点是"服务器完全看不见、不触发反作弊"。
**这个菜单不一样**：点格子用的是 `gm_giveswep` —— 一个**真实的控制台指令**，
会请求服务器给你武器。这是每个 GMod 玩家都会做的正常沙盒操作，但它**是服务器可见的**。

所以请理解：这是把一个**真实功能换上 MC 皮肤**，不是隐形外挂。
在严格的服务器（关闭了生成、或非 sandbox 模式）上，点格子可能没反应——
那是服务器不允许生成，跟本模块无关。

---

## 安装

需要先装好 **MCHUD**（本模块复用它的贴图 `mc_hud/widgets.png`、`mc_hud/icons.png`）。

把 `mc_spawnmenu` 文件夹放进 LJE 脚本目录：

```
%USERPROFILE%\.lje_scripts\mc_spawnmenu\
  ├── info.toml
  ├── main.lua
  ├── preview.html   (可选，只是预览图)
  └── README.md
```

启动 GMod（带 LJE），进游戏按 **Q** 就能看到菜单。

---

## 配置（main.lua 顶部）

```lua
local DEBUG      = false   -- 调试时设 true，会在 LJE 控制台打印信息；分享前设回 false
local OPEN_BIND  = "+menu" -- 开菜单的键。"+menu" 就是默认的 Q
local SLOT_SCALE = 2       -- 格子大小倍率，屏幕大/想要更大就调 3
local COLS       = 9       -- 列数（MC 创造背包就是 9 列，不建议改）
local ROWS       = 6       -- 每页行数，9x6 = 一页 54 个武器
```

**想换成别的键开菜单？**
把 `OPEN_BIND` 改成对应的 bind 名即可，比如 `"+menu_context"`（C 键）。
注意这里填的是 GMod 的 *bind 名*，不是键名。

---

## 它是怎么做到的（技术说明）

完全沿用 MCHUD 验证过的那套手法，所以在 LJE 沙盒里行为一致：

| 环节 | 做法 |
|------|------|
| 抢 Q 键 | `hook.pre("PlayerBindPress")` 在 DLib 之前拦住 `+menu`，`return true` 屏蔽原菜单 |
| 鼠标光标 | `gui.EnableScreenClicker(true/false)`，开菜单显示、关菜单隐藏 |
| 武器列表 | `list.Get("Weapon")`，和 GMod 自带生成菜单同一个库，只取可生成、非管理员限定的 |
| 画格子 | `surface.*` 基本图元画 MC 风格凹陷格子 + 悬停高亮 + 物品提示框 |
| 武器图标 | 复用 MCHUD 的图标解析（entities/*.png → killicon → 文字兜底） |
| 生成武器 | 点击执行 `gm_giveswep <类名>`（给到手上）；想生成到地上改成 `gm_spawnswep` |
| 翻页 | 滚轮，`InputMouseApply` 读 `GetMouseWheel()` |
| 渲染 | 双路：`ljeutil/render`（主）+ `HUDPaint`（兜底），每帧只画一次 |

---

## 想改的小地方

- **生成到地上而不是给到手上**：把 main.lua 里
  `RunConsoleCommand("gm_giveswep", cls)` 改成 `"gm_spawnswep"`。
- **每页更多/更少**：调 `ROWS`。
- **菜单打开时还能走动**：把 §9 里那段 "swallow movement-ish binds" 注释掉。

---

*written for "ba" by Arena.ai Agent Mode*
