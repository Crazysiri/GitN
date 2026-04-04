# GitN 应用内更新说明

本文说明 GitN 当前的应用内更新方案，包括：

- 普通用户如何使用应用内更新
- 更新源如何配置
- Sparkle 公钥如何生成与配置
- 发布者如何准备更新产物并上传发布

GitN 当前使用 [Sparkle](https://sparkle-project.org) 作为 macOS 应用内更新框架。

## 1. 设计原则

GitN 的更新架构分成两层：

- 应用侧：只认一个统一的 `Appcast / Feed URL`
- 发布侧：可以用 S3、CloudFront、GitHub Pages 或任意静态文件托管服务

这意味着应用不关心“你是传到 S3 还是别的服务”，应用只需要访问一个更新源地址，例如：

```text
https://updates.example.com/appcast.xml
```

S3 只是当前默认提供的一个发布器实现，不是应用配置模型的一部分。

## 1.1 更新源默认值与运行时覆盖

构建时可以通过环境变量传入：

```bash
SPARKLE_FEED_URL="https://updates.example.com/appcast.xml"
```

它的意义是给应用写入一个“出厂默认更新源”。

构建后，这个值会进入应用 `Info.plist` 的：

```xml
SUFeedURL
```

运行时，GitN 的更新源优先级是：

1. 用户在 `Settings → Updates` 里手动保存的 `Appcast URL`
2. 构建时写入应用包内的 `SPARKLE_FEED_URL`

所以 `SPARKLE_FEED_URL` 不是强制固定值，而是默认值。

如果构建时不传它，那么应用没有默认更新源，用户必须在设置里自己填写 URL，否则更新功能不可用。

## 2. 普通用户如何使用更新

### 2.1 菜单中手动检查更新

应用菜单中提供：

```text
Check for Updates…
```

点击后，GitN 会立即向当前配置的更新源检查是否有新版本。

### 2.2 设置中管理更新

打开：

```text
Settings → Updates
```

当前提供以下选项：

- `Appcast URL`
- `Automatically check for updates`
- `Automatically download updates`
- `Check for Updates Now`

说明如下：

- `Appcast URL`
  - 填写完整更新源地址
  - 例如：`https://updates.example.com/appcast.xml`
  - 如果留空，GitN 会回退到应用构建时写入的默认更新地址
- `Automatically check for updates`
  - 开启后，GitN 会自动周期性检查更新
- `Automatically download updates`
  - 开启后，发现新版本时会自动下载更新包
- `Check for Updates Now`
  - 立即发起一次手动检查

### 2.3 更新源填写规则

推荐填写完整 URL，而不是只写域名。

正确示例：

```text
https://updates.example.com/appcast.xml
https://cdn.example.com/gitn/stable/appcast.xml
```

不推荐：

```text
https://updates.example.com
```

原因是 Sparkle 一般需要访问明确的 appcast XML 文件地址，而不仅仅是站点根域名。

## 3. 为什么应用内更新使用 zip

GitN 当前的应用内更新包使用 `.zip`，这是 Sparkle 常见且合适的做法。

原因：

- 适合应用内自动下载和安装
- Sparkle 对 zip 更新链路支持成熟
- 不要求应用内更新必须使用 `.dmg`

因此当前建议是：

- 应用内更新：使用 `.zip`
- 首次下载安装分发：如有需要，可另外提供 `.dmg`

`.dmg` 不是这条应用内自动更新链路的必需条件。

## 4. Sparkle 公钥与私钥

GitN 当前使用 Sparkle 的 EdDSA（ed25519）签名机制。

这套机制包含一对密钥：

- 私钥：用于签名更新包，必须保密
- 公钥：写入应用包内，用于校验更新是否合法

### 4.1 私钥放哪里

Sparkle 的 `generate_keys` 工具会把私钥保存在当前机器的登录钥匙串（login keychain）里。

私钥：

- 不应该提交到 git
- 不应该直接写进仓库
- 应只保留在发布机器或专用签名机器上

### 4.2 公钥放哪里

公钥需要写入应用的 `Info.plist`，对应键名：

```xml
SUPublicEDKey
```

GitN 当前不是维护一个固定的 `Info.plist` 文件，而是由构建脚本 [build.sh](./build.sh) 动态生成，所以公钥通过环境变量传入：

```bash
SPARKLE_PUBLIC_ED_KEY="你的公钥"
```

如果不提供这个值，应用会认为更新功能不可用，并在设置中提示缺少公钥。

## 5. 如何生成 Sparkle 公钥

### 5.1 使用仓库里已经拉下来的 Sparkle 工具

在当前仓库里，SwiftPM 已经把 Sparkle 的工具下载到了：

- `GitN/.build/artifacts/sparkle/Sparkle/bin/generate_keys`
- `GitN/.build/artifacts/sparkle/Sparkle/bin/sign_update`
- `GitN/.build/artifacts/sparkle/Sparkle/bin/generate_appcast`

通常在你跑过一次下面任意命令后，这些工具就会存在：

```bash
swift build
swift test
./build.sh
```

如果这些路径还不存在，先执行一次 `swift build` 即可。

生成密钥命令：

```bash
/Users/jaden/GitX/GitN/.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

### 5.2 运行结果

第一次运行时，这个工具会：

1. 在你的登录钥匙串里生成并保存私钥
2. 在终端输出公钥

输出通常类似这样：

```xml
<key>SUPublicEDKey</key>
<string>pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=</string>
```

你真正需要拿去配置的是 `<string>` 里的那段值。

例如：

```text
pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ=
```

### 5.3 只需要生成一次

通常情况下，这个密钥只需要生成一次。

后续所有版本都使用同一把私钥签名，应用里始终携带对应的公钥。

如果以后要更换密钥，那属于“密钥轮换”场景，需要额外谨慎处理，不建议随意换。

## 6. 如何把 Sparkle 公钥配置进 GitN

### 6.1 开发构建

如果只是本地构建测试：

```bash
SPARKLE_PUBLIC_ED_KEY="你的公钥" \
SPARKLE_FEED_URL="https://updates.example.com/appcast.xml" \
./build.sh
```

### 6.2 正式发布构建

正式发布时建议这样：

```bash
APP_VERSION=1.2.0 \
APP_BUILD=1200 \
SIGNING_IDENTITY="Developer ID Application: Your Name" \
SPARKLE_PUBLIC_ED_KEY="你的公钥" \
SPARKLE_FEED_URL="https://updates.example.com/appcast.xml" \
./Scripts/build_release.sh
```

如果 `SPARKLE_PUBLIC_ED_KEY` 缺失，应用会提示：

```text
Sparkle public key is missing from the app bundle.
```

这说明更新功能没有被正确启用。

## 7. 发布者如何准备更新

GitN 当前把“准备更新产物”和“上传到服务器”拆开。

主流程分为两段：

1. 准备更新产物
2. 上传更新产物

### 7.1 一条命令准备更新产物

脚本：

```bash
./Scripts/build_release.sh
```

完整示例：

```bash
APP_VERSION=1.2.0 \
APP_BUILD=1200 \
SIGNING_IDENTITY="Developer ID Application: Your Name" \
SPARKLE_PUBLIC_ED_KEY="你的公钥" \
SPARKLE_FEED_URL="https://updates.example.com/appcast.xml" \
./Scripts/build_release.sh
```

这个脚本现在会一次完成：

- release 构建
- 生成 `.app`
- 嵌入 `Sparkle.framework`
- 生成带 `SUFeedURL` / `SUPublicEDKey` 的 `Info.plist`
- 使用提供的签名身份进行代码签名
- 打包 Sparkle 使用的 `.zip`
- 生成 `build/updates/appcast.xml`

如果 zip 的公网下载前缀和 appcast 地址不在同一个静态目录下，需要额外指定：

```bash
SPARKLE_DOWNLOAD_URL_PREFIX="https://downloads.example.com/gitn"
```

这会传给 Sparkle 的 `generate_appcast --download-url-prefix`，避免生成错误的 zip 下载地址。

执行完成后，主要产物在：

```text
build/GitN.app
build/updates/
```

其中 `build/updates/` 至少会包含：

- 更新 zip
- `appcast.xml`

### 7.2 `SPARKLE_BIN_DIR` 从哪里来

通常你不需要自己手动设置 `SPARKLE_BIN_DIR`。

脚本会自动尝试从以下位置查找 Sparkle 工具：

- `GitN/.build/artifacts/sparkle/Sparkle/bin`
- `GitN/.build/checkouts/Sparkle`
- `/Applications/Sparkle/bin`

在当前仓库里，最常见的是：

```text
GitN/.build/artifacts/sparkle/Sparkle/bin
```

这个目录通常会在你执行过一次：

```bash
swift build
```

或：

```bash
swift test
```

之后由 SwiftPM 自动下载生成。

只有当你的 Sparkle 工具不在这些默认位置时，才需要手动设置：

```bash
SPARKLE_BIN_DIR=/path/to/Sparkle/bin
```

如果你的 `SPARKLE_FEED_URL` 是带 query 参数的代理地址，例如：

```text
https://example.com/api/download?source=gitn/appcast.xml
```

那么还建议同时设置：

```bash
SPARKLE_DOWNLOAD_URL_PREFIX="https://example.com/static/gitn"
```

否则 `generate_appcast` 在推导 zip 下载地址时很容易得到错误结果。

对于 GitN 当前已经适配的一类地址：

```text
https://host/config/s3-presign/download?bucket=xxx&source=gitn/appcast.xml
```

`build_release.sh` 会自动推导出：

```text
https://host/config/s3-presign/download?bucket=xxx&source=gitn
```

然后让 Sparkle 生成：

```text
https://host/config/s3-presign/download?bucket=xxx&source=gitn/GitN-1.3.0-1300.zip
```

如果你的下载接口规则不是这种模式，还是应显式传入 `SPARKLE_DOWNLOAD_URL_PREFIX`。

### 7.3 上传到 S3

默认上传器是 S3：

```bash
S3_BUCKET=my-updates \
S3_PREFIX=gitn/stable \
AWS_REGION=us-east-1 \
./Scripts/publish_update.sh build/updates
```

这个命令默认调用：

```text
Scripts/publishers/s3.sh
```

### 7.4 上传到其他服务器

如果你不是传到 S3，而是传到自己的服务器，可以使用 rsync 上传器：

```bash
UPDATE_PUBLISHER_SCRIPT=./Scripts/publishers/rsync.sh \
RSYNC_DESTINATION=deploy@example.com:/var/www/updates/gitn \
./Scripts/publish_update.sh build/updates
```

也可以替换成你自己的上传脚本：

```bash
UPDATE_PUBLISHER_SCRIPT=/abs/path/to/your-publisher.sh \
./Scripts/publish_update.sh build/updates
```

要求只有一个：

- 这个脚本接收一个参数，即准备好的 `build/updates` 目录路径

上传侧只负责把静态文件发出去。应用侧无需修改，仍然只认统一的 feed URL。

## 8. 签名与 notarization 说明

需要区分两类签名：

### 8.1 Apple 代码签名

这是 macOS 应用本体的签名，建议正式发布使用：

- `Developer ID Application`
- notarization

当前仓库原本的 `build.sh` 默认使用 ad-hoc 签名，只适合本地开发，不适合作为正式线上更新发布方案。

### 8.2 Sparkle EdDSA 签名

这是 Sparkle 对更新包的签名校验机制。

即使应用已经做了 Apple 代码签名，Sparkle 仍然要求用它自己的 EdDSA 机制来校验更新内容。

因此正式发布时，两层都要考虑：

- App 本体：Developer ID + notarization
- 更新内容：Sparkle EdDSA 签名

## 9. 当前实现的范围

目前这套实现默认是：

- 单一更新通道
- 单一 feed URL 配置
- 不区分 S3 / CloudFront / 其他后端类型
- 不做 beta / stable 多通道切换
- 不做 delta updates，只做完整包更新

如果未来要扩展，也建议继续遵守当前结构：

- 应用层只认统一 feed URL
- 发布层自由替换底层存储服务

## 10. 常见问题

### 10.1 为什么启动后提示缺少 Sparkle 公钥？

因为当前构建产物里没有写入：

```text
SUPublicEDKey
```

也就是你没有在构建时传入：

```bash
SPARKLE_PUBLIC_ED_KEY="..."
```

### 10.2 公钥和私钥都要放进仓库吗？

不需要。

- 公钥：进入应用构建配置
- 私钥：只保留在钥匙串或安全发布环境中

### 10.3 应用内更新一定要用 dmg 吗？

不需要。

GitN 当前应用内更新链路使用 `.zip`，这是合理且推荐的。

### 10.4 为什么应用只配置一个 URL，不配置“S3 类型”？

因为 S3 属于发布实现细节，不属于应用内更新协议本身。

应用真正需要知道的只有：

```text
去哪里拿 appcast.xml
```

这也是当前架构里“应用侧与发布侧解耦”的核心。
