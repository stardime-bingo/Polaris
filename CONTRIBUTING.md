# Contributing to Polaris

欢迎帮助 Polaris 变得更好。小而完整的改动最容易评审；较大的功能或交互调整请先开 Issue 说明使用场景。

## 本地开发

需要 macOS 与 Xcode 26+。从仓库根目录运行：

```bash
./script/build_and_run.sh          # 独立开发预览
./script/build_and_run.sh --demo   # 虚构数据示例
./script/build_and_run.sh --debug  # 用 LLDB 启动预览
```

完整构建命令见 [BUILDING.md](docs/BUILDING.md)。保留的 Xcode target / scheme 名为 `Docket`，生成的产品名为 `Polaris`。

## 提交改动

1. 从当前 `main` 创建分支，保持改动范围聚焦。
2. 涉及数据时兼容旧 JSON；涉及同步时保持列表授权边界、错误可恢复与本地数据完整。
3. 运行 `./run-tests.sh`、`./script/test_step_persistence.sh` 和 `./build.sh`。
4. 界面改动实际打开应用检查，附使用虚构数据的截图。确认浅色/深色、长内容、设置导航、键盘输入与小屏布局。
5. PR 写清具体问题、改变后的行为和验证范围。不要把编译结果当作实机或同步验收。

UI 保持原生与克制。请优先复用已有控件、间距和语义颜色，保留减少动态效果/透明度适配，不为装饰引入常驻动画或网络依赖。

## 数据与附件

- 不提交个人目标、提醒事项 ID、账户信息、录屏中的真实数据或本地诊断记录。
- `.local/`、`build/`、应用包和用户 Xcode 设置不会进入版本库。
- 用 `--demo` 生成独立示例；不要把个人导出文件直接用作测试样本。
- 提交的代码按仓库 MIT License 提供，请保留原作者署名及第三方许可。

普通问题使用 GitHub Issues。安全问题请阅读 [SECURITY.md](SECURITY.md)。
