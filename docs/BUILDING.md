# 构建、预览与分发

## 工具链

- macOS 14+ 运行环境。
- Xcode 26+，包含 macOS 26 SDK、`swiftc` 与支持 `.icon` 的 `actool`；仅 Command Line Tools 不足以编译当前图标资产。
- Python 3 用于生成可选演示数据。应用本身不依赖 Python，也没有第三方 Swift 包。

先检查 `xcode-select -p`、`xcodebuild -version` 和 `xcrun --sdk macosx --show-sdk-version`。多版本 Xcode 可以按命令设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`，无需改动全局选择。

## 命令行构建

```bash
./build.sh
open build/Polaris.app
```

脚本默认生成发布优化包并进行 ad-hoc 签名，架构跟随当前机器。Apple Silicon / macOS 26 已验证，Intel 与 macOS 14/15 的实机验证不应仅凭编译结果推定。

```bash
POLARIS_BUILD_MODE=debug ./build.sh
POLARIS_BUILD_DIR="$PWD/build/custom" ./build.sh
```

构建不安装应用、不复制正式数据；但**直接打开正式身份的 `Polaris.app` 会使用该身份对应的数据目录和系统权限**。已有正式版用户请使用下方预览命令开发。

## 隔离预览与演示

```bash
./script/build_and_run.sh
./script/build_and_run.sh --demo
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --verify
```

普通预览使用 `com.bingowu.polaris.preview`、`build/preview/` 与 `.local/preview-data/`。演示使用 `com.bingowu.polaris.demo.preview`、`build/demo/` 与 `.local/demo-data/`；首次运行创建虚构目标，后续运行保留演示中的编辑。

两者均使用独立偏好设置，禁用正式提醒同步、通知调度、登录项修改及系统全局快捷键。`--verify` 只证明进程启动，不证明界面或交互正确。源码、资源与工具链未改变时，脚本复用签名有效的预览构建。

单独生成新的示例数据：

```bash
python3 script/make_demo_data.py "$PWD/.local/another-demo"
```

脚本仅接受空目录，不覆盖已有文件，不读取用户目标。自定义预览启动必须同时使用以 `.preview` 结尾的独立 bundle ID 与明确的绝对 `--preview-data` 路径，不能只给正式身份传这个参数。

## Xcode

打开 `Docket.xcodeproj`，选择 `Docket` scheme。产品名是 Polaris；保留工程名以减少无关重命名。构建配置不包含开发者 Team ID，命令行构建与 Xcode 均禁用上游自购打赏入口。

```bash
xcodebuild -project Docket.xcodeproj -scheme Docket \
  -configuration Release -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

该命令只验证构建。Xcode 默认使用 App Sandbox，数据目录与命令行包不同；运行或自行分发时需要配置自己的签名身份和实际 bundle ID。

## 检查

```bash
./run-tests.sh
./script/test_step_persistence.sh
codesign --verify --deep --strict build/Polaris.app
```

CI 使用 GitHub 官方 [`macos-26` runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)，执行逻辑与持久化检查、命令行构建和 Xcode Release 构建。原生界面、外部账户同步与系统授权仍需对应环境的实际检查。

## 对外分发

当前仓库发布源码，未附公证安装包。ad-hoc 签名只适用于本机构建，不等于可被其他 Mac 信任的发行签名。

正式分发需要自己的 Developer ID、合适的 hardened runtime 与 entitlements、有效的嵌套代码签名，以及 Apple notarization/stapling。完成后还应在另一台 Mac 检查首次启动、系统授权、提醒同步与升级数据。不要提交签名私钥、证书密码或公证凭据。
