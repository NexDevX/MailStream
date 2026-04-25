# InboxOne

基于 **SwiftUI + AppKit** 的 macOS 原生邮箱客户端原型。

当前仓库已经包含：

- 一个可直接生成的 macOS App 工程
- 一个最小可运行的三栏邮件界面
- 一个本地打包 `.dmg` 的脚本
- 一个 GitHub Actions 自动构建和发布安装包的流程
- 一套更清晰的工程基线：依赖装配、仓储层、文档和统一命令入口

## 当前版本范围

这版只解决两个问题：

- 有一个接近设计稿气质的桌面页面
- 能在 macOS 本地编译成 `.app`，并进一步打包成 `.dmg`

这版还没有接入真实邮箱账号、同步、数据库和离线缓存。

## 本地运行

先生成 Xcode 工程：

```bash
xcodegen generate
```

然后可以用 Xcode 打开：

```bash
open MailClient.xcodeproj
```

也可以直接命令行编译：

```bash
xcodebuild \
  -project MailClient.xcodeproj \
  -scheme MailClient \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

统一命令入口：

```bash
make icon
make generate
make build
make test
make package
```

`make icon` 会重建仓库里的 macOS `AppIcon.appiconset` 和 `AppIcon.icns`，方便后续替换品牌图标时保持资源可重复生成。

## 打包 DMG

执行：

```bash
./scripts/build_dmg.sh
```

输出位置：

```bash
build/Release/MailStrea.dmg
```

## GitHub CI/CD

仓库已经包含 GitHub Actions 工作流：

- `push 任意分支`：自动构建 DMG，上传 Actions artifact，用于验证分支是否可发布
- `pull_request -> main`：自动构建 DMG，验证合并前状态
- `push main`：自动构建 DMG，上传 artifact，并更新一个固定的 `latest-main` 预发布下载页
- `push v* tag`：自动构建 DMG，并发布到 GitHub Releases 供用户下载

工作流文件：

```bash
.github/workflows/build-release.yml
```

GitHub 仓库需要确认：

1. `Settings -> Actions -> General -> Workflow permissions` 选择 `Read and write permissions`
2. 允许 GitHub Actions 创建和更新 Releases
3. 仓库至少有一个 `main` 分支后，再把 `main` 设为默认分支

最小发布闭环建议：

1. 先推送功能分支，等 Actions 构建通过
2. 合并到 `main` 后，从 `latest-main` 预发布页或本次 Actions artifact 下载测试包
3. 需要正式版本时，再创建版本标签并推送

示例：

```bash
git push origin main
git tag v0.1.0
git push origin v0.1.0
```

完成后，用户可以在 GitHub 的 `Releases` 页面下载：

- `Latest Preview` 对应的滚动预发布安装包
- `MailStrea.dmg`
- `MailStrea.dmg.sha256`

如果只是内部预览，不发版本标签也可以，直接使用 `latest-main` 预发布页或对应 Actions artifact。

## 目录说明

- `MailClient/`: 应用源码
- `project.yml`: `xcodegen` 工程描述
- `Makefile`: 统一开发命令入口
- `docs/architecture.md`: 分层和依赖约束
- `scripts/build_dmg.sh`: 本地生成 `.dmg`

## 注意

当前生成的是**未签名**应用，适合本地开发和小范围测试分发。  
如果后面要给普通用户稳定安装，还需要补：

- Developer ID 签名
- notarization 公证
