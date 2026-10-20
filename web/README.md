# 多多 Fitness Web MVP

这是 `fitness-app` 的 Windows / Web 版本第一阶段。

## 现在能做什么

- Windows / Mac / iPhone 浏览器打开
- 可安装为 PWA（支持浏览器“安装应用 / 添加到主屏幕”）
- 首页 Daily Coach 简单建议
- 记录饮食、体重、羽毛球、力量训练
- 胸 / 肩 / 背 / 腿固定模板
- 自动读取 Web 端上一次同动作记录
- 本地 JSON 导出 / 导入备份
- 离线缓存基础页面

## 目前的数据位置

当前 Web MVP 使用浏览器 `localStorage`。

这意味着：

- Windows 上的数据不会因为 iPhone Xcode 7 天签名过期而失效。
- 换浏览器或清除浏览器数据前，建议先在“设置 → 数据与备份 → 导出 JSON”保存备份。
- 目前不会自动和 iPhone SwiftData 同步。

## Windows 启动

不要直接双击 `index.html`。PWA / Service Worker 需要通过本地 HTTP 服务打开。

如果 Windows 已安装 Python：

```powershell
cd web
python -m http.server 8080
```

浏览器打开：

```text
http://localhost:8080
```

然后可以在 Edge / Chrome 菜单里选择“安装此站点为应用”。

## 与 iPhone App 的关系

iPhone App 仍负责：

- Apple Health / Apple Watch
- HealthKit 睡眠、体重、运动读取
- 现有 B.ai 食物照片识别
- 原生 SwiftData 数据

Web MVP 当前负责：

- Windows 长期可用入口
- 手动记录与查看
- 本地备份
- 训练模板 / Agent 基础逻辑

## 下一阶段：真正双端同步

需要新增一个云端数据层，然后 iPhone 和 Web 都读写同一套 API。

建议优先选择：

- Supabase（Postgres + Auth + Storage），或
- Firebase（Auth + Firestore + Storage）

必须保持：

- API Key / B.ai 密钥不能硬编码在 Web 前端
- Apple Health 数据只能由 iPhone 读取后上传
- 照片放对象存储，不直接塞进数据库
- 所有用户数据按用户 ID 隔离
- 支持导出完整 JSON / Markdown 档案

详细字段映射见 `SYNC_ARCHITECTURE.md`。
