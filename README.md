# 拾光整理 · EasyPhoto

EasyPhoto 是一个原生 HarmonyOS 照片整理应用。它支持逐张浏览系统图库、点击或拖动分类、可撤销的待删标记，以及按相册放映回忆。分类时先保存并校验目标相册中的副本，用户结束整理时再按设置处理本轮原图。回收使用系统确认。

## 构建

项目使用 ArkTS、ArkUI、Stage、OHPM 和 Hvigor。公开源码版本为 0.3.10，目标 SDK 为 26.0.0，最低系统配置为 HarmonyOS 6.1.0（API 23）。

1. 在全新检出的项目根目录将 `build-profile.template.json5` 复制为 `build-profile.json5`，再用 DevEco Studio 打开项目并同步 OHPM 依赖。
2. 在 DevEco Studio 中构建 HAP，也可在 Windows PowerShell 中运行 `.\scripts\build.ps1 -DevEcoHome 'C:\path\to\DevEco Studio'`，并填写实际安装目录。
3. 运行应用需要自行配置签名和匹配的调试设备。图库写入能力还取决于你的应用标识、权限和 Profile。请将签名材料与个人设备数据保留在本地。

主机测试使用支持 `node:sqlite` 的 Node.js，可从根目录运行 `node scripts/test-photo-practice.cjs`、`node scripts/test-slideshow.cjs` 等脚本。测试使用 DevEco Studio 随附的 TypeScript；如安装目录不同，请先设置 `DEVECO_STUDIO_HOME`。主机测试用平台替身运行。

## 验证范围

此版本为开发快照。已知问题包括部分拖动分类命中异常及放映状态栏对比度问题。建议用应用内置练习熟悉手势，并用可丢弃样本验证图库流程。目标设备上的分类与回收仍需验收。

## 许可证

项目原创源码采用 [MIT](LICENSE)。第三方图标和示例照片沿用其各自许可与署名，见[第三方声明](THIRD_PARTY_NOTICES.md)。
