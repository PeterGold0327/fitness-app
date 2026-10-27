# 多多 Fitness 微信小程序

这是 Windows/PWA 的微信小程序前端。数据继续使用同一个 Supabase `fitness_snapshots`，Apple Watch / Health Auto Export、饮食、训练、体重都会共享同一份数据。

## 当前已完成

- 今天：首页热量、P/C/F、体重、今日饮食、今日运动
- 默认早餐：一键记录 + 可编辑模板，默认使用 2026-10-27 早餐（560 kcal / P31 / C68 / F20）
- 记录：相机 + 相册 + AI 食物识别 + 手动记录
- 训练：动作、组、重量、次数、RPE；Apple Watch 功能性力量训练的时长/消耗继续从云端合并
- 日历：按天查看训练、羽毛球、饮食和身体数据
- 进展：体重与训练概览
- Supabase 邮箱/密码登录，session 自动保存在微信本地

## 1. 微信开发者工具导入

1. 下载并打开微信开发者工具。
2. 选择 **导入项目**。
3. 项目目录选择仓库中的：`wechat-miniprogram/`
4. `project.config.json` 已设置 `miniprogramRoot: "miniprogram/"`。
5. 目前 AppID 是 `touristappid`，开发阶段可打开界面；要在自己的微信上长期体验/上传版本，需要把它换成你自己的小程序 AppID。

## 2. Supabase 网络域名

当前后端：

`https://xpngredrhqgolsiexwjs.supabase.co`

小程序所有 Auth、数据库 REST 和 Edge Function 请求都走这个域名。图片在客户端压缩后读取为 base64，再用 `wx.request` 调 `analyze-food`，所以当前只依赖 **request 合法域名**，没有使用 `wx.uploadFile`。

### 开发工具先测试

开发者工具里可先开启“开发环境不校验请求域名 / TLS / HTTPS 证书”（具体菜单名称可能随工具版本变化）。项目配置目前也设置了 `urlCheck: false` 方便开发。

### 真机/上传前

在微信公众平台的小程序后台，把 Supabase 域名添加到服务器 `request` 域名：

`https://xpngredrhqgolsiexwjs.supabase.co`

如果微信后台因为主体、备案或域名规则不接受第三方 Supabase 域名，不要反复试。下一步应加一个微信可接受的 HTTPS 代理域名（例如国内合规云函数/自有备案域名），小程序只改 `config.js`，Supabase 数据库不用迁移。

## 3. 登录

用 Windows 网页目前相同的 Supabase 邮箱和密码登录。首次成功后 access/refresh token 会保存在微信本地；过期时会自动 refresh。

## 4. 默认早餐

首页默认早餐目前是：

- 250g 酸奶
- 2 个燕麦
- 30g 蓝莓
- 12g 南瓜子
- 1 根香蕉
- 560 kcal
- P 31g / C 68g / F 20g

首页点“一键记录”只会添加一次；点“编辑”可以修改模板。模板保存在 `snapshot.profile.breakfastTemplate`，不是写死在设备本地。

## 5. 拍照 / 相册识别

进入底部“记录”：

1. 点图片区域。
2. 选择相机或相册。
3. 小程序压缩图片。
4. 调用 Supabase Edge Function `analyze-food`。
5. AI 返回食物项目、克数、热量和 P/C/F。
6. 用户可逐项修改后保存。

## 6. 数据原则

- 小程序和 Windows 共用 `fitness_snapshots`。
- 不另建第二套饮食/训练数据库。
- Apple Watch 的“功能性力量训练”属于健身，时间和 kcal 合并到当天健身记录，不额外重复显示。
- 日期按本地日期处理，避免 UTC 导致记录跑到前一天。

## 下一步（拿到 AppID 后）

1. 替换 `project.config.json` 的 `appid`。
2. 开发者工具编译。
3. 用现有 Supabase 账号登录。
4. 测试：默认早餐 → 相册识别 → 相机识别 → 训练 → 日历。
5. 如果域名被微信后台拒绝，再增加合规代理层，不迁移现有 Supabase 数据。
