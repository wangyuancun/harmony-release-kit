# HarmonyOS 应用上架模板

一个人从零把 HarmonyOS 应用做到华为应用市场上架的**可复用模板仓**：
工程骨架 + 签名脚本 + 截图文案工具 + 一份按真实踩坑顺序写成的流程文档。

---

## 0. 交付说明（先读这一节）

### 这个仓不包含什么

- **不含任何业务代码**：只有一个可编译的最小页面，业务页面自己替换。
- **不含证书、私钥、口令**：`signing/` 下只有脚本，没有任何 `.p12` / `.cer` / `.p7b` / `.csr`。
- **不含个人信息**：没有真实包名、手机号、邮箱、开发者主体名称，全部是 `【】` 占位符。
- **不含原应用的业务素材**：图标是脚本生成的中性占位图（灰底 + 白色 T），不是任何 IP 素材。
- **不含 `.hvigor/`、`build/` 等构建产物**，已在 `.gitignore` 排除。

### 从 clone 到跑通，大概 5 步

| 步 | 做什么 | 命令/入口 |
| --- | --- | --- |
| 1 | 装 **Release 版** DevEco Studio（不要 Beta） | 见第 1 节 |
| 2 | 改包名/应用名/图标 | 见第 2 节 |
| 3 | 编译出未签名 HAP | `hvigorw --mode module -p product=default assembleHap` |
| 4 | 在 AGC 申请发布证书与 Profile（人工，需实名账号） | 见第 6 节 |
| 5 | 签名 → 出 `.app` → 上传 | `signing/sign-release.sh` + `assembleApp` |

> 只跑模拟器的话，第 4、5 步可以跳过：未签名 HAP 可以直接 `hdc install`。

### 目录结构

```
harmony-app-template/
├── README.md                       # 本文档
├── .gitignore
├── AppScope/
│   ├── app.json5                   # 包名/版本/图标/应用名（占位 com.example.template）
│   └── resources/base/
│       ├── element/string.json     # app_name
│       └── media/app_icon.png      # 中性占位图标 512×512
├── build-profile.json5             # compile/compatible/targetSdkVersion = 26.0.0
├── oh-package.json5
├── hvigorfile.ts
├── hvigor/hvigor-config.json5
├── entry/                          # 唯一模块
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   ├── oh-package.json5
│   ├── obfuscation-rules.txt
│   └── src/main/
│       ├── module.json5            # EntryAbility、pages 入口、零权限
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets
│       │   └── pages/Index.ets     # 最小可编译页面
│       └── resources/base/
│           ├── element/{string,color}.json
│           ├── profile/main_pages.json
│           └── media/{app_icon,startIcon}.png
├── signing/
│   ├── gen-csr.sh                  # 生成 EC 密钥库 + CSR（参数化）
│   ├── sign-release.sh             # 签 HAP/APP（口令交互输入）
│   └── ptysign.py                  # 等提示出现再喂口令的 pty 驱动
├── screenshots/
│   ├── capture-emulator.sh         # hdc 抓图
│   └── make-store-shots.py         # 1080×1920 / 9:16 等比缩放 + 补边
└── templates/
    ├── privacy-policy.md           # 隐私政策模板
    ├── ai-disclosure.md            # AI 功能声明填写口径
    └── store-listing.md            # 上架物料模板
```

---

## 1. 环境：必须用 Release 版 DevEco Studio

### 为什么不能用 Beta

Beta SDK 打出的包，`pack.info` 里 `apiVersion.releaseType` 会是 **`Beta1`**，
AGC 预审/审核会因此驳回。这不是「可能」——本次实测的 Beta 包字段就是 `Beta1`，
换成 Release 工具链重打后才变成 `Release`。

本次验证使用：

| 项 | 值 |
| --- | --- |
| IDE | **DevEco Studio 26.0.0**（build `DS-261.23567.138.36.2600865` / 26.0.0.865） |
| 安装路径 | `~/Applications/DevEco-Studio-26.0.0.app`（装在用户目录，不需要管理员密码） |
| SDK | HarmonyOS **26.0.0**，`version 26.0.0.105`，`releaseType Release` |
| hvigor | 6.26.9（IDE 自带 `Contents/tools/hvigor/bin/hvigorw`） |
| JBR | IDE 自带 `Contents/jbr/Contents/Home` |

> Beta 版（26.0.1.290，SDK 26.0.1.120 / Beta1）可以留作对照，但**不要用它出上架包**。
> 两个 IDE 可以同时在 `~/Applications` 下共存，互不覆盖。

### 环境变量（每个新终端执行一次）

```bash
export DEVECO="$HOME/Applications/DevEco-Studio-26.0.0.app/Contents"
export DEVECO_SDK_HOME="$DEVECO/sdk"
export JAVA_HOME="$DEVECO/jbr/Contents/Home"
export NODE_HOME="$DEVECO/tools/node"
export HVIGOR_USER_HOME="$HOME/Library/Caches/hvigor-home-release"
export PATH="$DEVECO/tools/hvigor/bin:$DEVECO/tools/ohpm/bin:$DEVECO/tools/node/bin:$PATH"
```

如果装在别处，把 `DEVECO` 指向对应 `.app/Contents`，签名脚本用 `--deveco` 或
`DEVECO_HOME` 覆盖。

### 确认 SDK 是 Release

```bash
cat "$DEVECO/sdk/default/sdk-pkg.json"
# 期望： "platformVersion": "26.0.0", "releaseType": "Release", "version": "26.0.0.105"
```

---

## 2. 用模板开一个新应用

改四处即可，**包名必须在 AGC 创建应用之前定好**（创建后不可修改）：

| 文件 | 改什么 |
| --- | --- |
| `AppScope/app.json5` | `bundleName`（如 `com.yourname.yourapp`）、`vendor`、`versionCode`、`versionName` |
| `AppScope/resources/base/element/string.json` | `app_name`（应用名，≤15 汉字） |
| `entry/src/main/resources/base/element/string.json` | `EntryAbility_label` 等展示名 |
| `*-/media/{app_icon,startIcon}.png` | 换成正式图标（216 或 1024，正方形，PNG ≤3 MB） |

同步修改：

- `oh-package.json5` / `entry/oh-package.json5` 的 `name`、`description`
- `entry/src/main/ets/pages/Index.ets`：替换成业务页面（保留 `@Entry`+`@Component`+`build()`）
- 需要权限时在 `entry/src/main/module.json5` 加 `requestPermissions`，并同步隐私政策

> 模板默认**零权限、无第三方依赖**，与隐私政策模板的口径一致。
> 一旦加权限或 SDK，必须同步改隐私政策和 AGC 隐私标签，否则会被判「声明与实际不符」。

---

## 3. 编译：HAP 与 APP

### 3.1 未签名 HAP（自测/模拟器）

```bash
cd harmony-app-template
hvigorw clean --no-daemon
hvigorw --mode module -p product=default assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`

### 3.2 未签名 APP（上架用，AGC 只收 `.app`）

```bash
hvigorw --mode project -p product=default -p buildMode=release assembleApp --no-daemon
```

产物：`build/outputs/default/<工程名>-default-unsigned.app`

> 也可以用 IDE：`Build > Build App(s)`。
> AGC 上传的是 **`.app`**，不是 `.hap`；单 HAP 工程打出来的 `.app` 里只含一个 hap。

### 3.3 模拟器安装（可选）

```bash
HDC="$DEVECO/sdk/default/openharmony/toolchains/hdc"
$HDC install entry/build/default/outputs/default/entry-default-unsigned.hap
$HDC shell aa start -a EntryAbility -b com.example.template
```

> 未签名 HAP 在模拟器上可以直接装；真机和上架必须签名。

---

## 4. 出包后自查：`releaseType` 必须是 Release

`pack.info` 就在产物旁边：

```bash
# HAP
cat entry/build/default/outputs/default/pack.info

# APP
cat build/outputs/default/pack.info
```

用一条命令判断（推荐，避免肉眼漏看）：

```bash
python3 - <<'EOF'
import json
for p in ["entry/build/default/outputs/default/pack.info", "build/outputs/default/pack.info"]:
    try:
        d = json.load(open(p))
    except FileNotFoundError:
        continue
    m = d["summary"]["modules"][0]["apiVersion"]
    print(p, "apiVersion.releaseType =", m.get("releaseType"),
          "| app.apiReleaseType =", d["summary"]["app"].get("apiReleaseType"))
EOF
```

期望输出：

```
... apiVersion.releaseType = Release | app.apiReleaseType = None
```

说明：

- **`apiVersion.releaseType` 必须是 `Release`**。出现 `Beta1` 就是用了 Beta SDK，重打。
- `app.apiReleaseType` 在本次未签名的 `.app` 里**没有出现**（`None` 是正常的）；
  如果出现了，也必须是 `Release`。以 `apiVersion.releaseType` 为准。
- 只想快速确认：`grep -o '"releaseType": *"[^"]*"' <pack.info>`。

---

## 5. EC 密钥库与 CSR

### 为什么 RSA 不行

HarmonyOS 应用签名要求 **SHA256withECDSA**。AGC 上传证书时会校验 CSR 的
公钥算法与曲线，RSA 生成的 CSR 会直接提示 **`上传的CSR文件无效`**。

正确参数（三项缺一不可）：

```bash
-keyalg EC -groupname secp384r1 -sigalg SHA256withECDSA
```

### 生成（脚本，参数化）

```bash
bash signing/gen-csr.sh \
  --out-dir ~/keys \
  --alias my_release \
  --dname "CN=Your Name, OU=Dev, O=Your Org, L=City, ST=Province, C=CN"
```

脚本会调用 `keytool`，口令由 keytool 在终端提示输入（两次以上），
**不接受口令参数、不写文件、不进 shell history**。产出：

- `~/keys/my_release.p12` —— 密钥库，**务必备份**，丢了无法再签同一应用
- `~/keys/my_release.csr` —— 上传 AGC 创建发布证书

### 等价的手工命令

```bash
keytool -genkeypair \
  -alias my_release \
  -keyalg EC -groupname secp384r1 -sigalg SHA256withECDSA \
  -dname "CN=Your Name, OU=Dev, O=Your Org, L=City, ST=Province, C=CN" \
  -validity 9125 \
  -keystore my_release.p12 -storetype PKCS12

keytool -certreq \
  -alias my_release \
  -keystore my_release.p12 \
  -file my_release.csr \
  -sigalg SHA256withECDSA
```

### 上传前自查 CSR

```bash
openssl req -in my_release.csr -noout -text \
  | grep -E "Public Key Algorithm|ASN1 OID|Signature Algorithm"
```

期望看到：

```
Public Key Algorithm: id-ecPublicKey
ASN1 OID: secp384r1
Signature Algorithm: ecdsa-with-SHA256
```

> 密钥库 `validity` 可以填 25 年，但 **AGC 签发的证书有效期为 3 年**，
> 到期前要重新走一次证书/Profile 流程。

---

## 6. AGC：建应用 → 发布证书 → 发布 Profile

顺序不能乱：**CSR → 证书 → Profile**。Profile 依赖证书，证书依赖 CSR 对应的密钥对。

### 6.1 前置

1. 华为开发者账号 + **实名认证**（个人：身份证 + 人脸；企业：营业执照 + 对公信息）
2. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
3. 「我的项目」→ 新建项目 → 「添加应用」

### 6.2 创建应用

- 平台选 **HarmonyOS（App）**
- 包名填工程 `AppScope/app.json5` 里的 `bundleName`，**必须完全一致**
- 创建后记下 **APP ID**，后续证书/Profile 都基于它
- 包名一旦创建不可修改；提示 `bundle name is already in use` 说明已被占用，
  只能改工程包名后重新创建

### 6.3 创建发布证书

1. 项目 →「证书、APP ID 和 Profile」→「证书」→ 新增
2. 证书名称：如 `my_release`
3. 证书类型：**发布证书**
4. 上传 5.1 生成的 **`.csr`**
5. 创建成功后下载 **`.cer`**（PEM 格式，含 3 级证书链）

> 这里最容易踩的坑：上传 RSA 的 CSR → `上传的CSR文件无效`。
> 换 EC 必须同时换密钥库（新 p12 + 新 CSR），不能只重生成 CSR。

### 6.4 创建发布 Profile

1. 同页面 →「Profile」→ 新增
2. 类型：**发布**
3. **绑定 6.3 创建的发布证书**
4. 绑定对应 App ID / 包名
5. 创建成功后下载 **`.p7b`**（DER 格式 PKCS#7，里面绑定包名）

> 调试 Profile 还需要设备 UDID，与设备绑定；**上架用发布 Profile，不需要 UDID**。

### 6.5 需要下载回来的三件套

| 文件 | 来源 | 用途 |
| --- | --- | --- |
| `.p12` | 本地 `gen-csr.sh` 生成 | 私钥，签名时用 |
| `.cer` | AGC 发布证书下载 | 证书链 |
| `.p7b` | AGC 发布 Profile 下载 | 绑定包名与证书 |

三者缺一不可；`.p12` 丢了只能重新申请证书（等于换签名身份）。

---

## 7. 签名与出包

### 为什么不用 `build-profile.json5` 的 `signingConfigs`

1. `signingConfigs.storePassword / keyPassword` 只接受 DevEco Studio 用
   `p12` 同目录下 `material/` 密钥材料加密出的**密文**；没有 `material/`
   会直接报 `SIGNING_FAILED_*` / `KEY_PASSWORD_VALID_FAILED`。
2. 即使填了密文，hvigor 解密后仍会把明文口令作为 `-keystorePwd` / `-keyPwd`
   传给 java 子进程（`ps` 可见），不满足「口令不进命令行」。

所以命令行签名统一走 `signing/sign-release.sh`。

### 口令是怎么做到「不落盘、不进 argv」的

- 脚本不接收口令参数；`ptysign.py` 用 `getpass` 从 `/dev/tty` 读，不回显。
- 口令只存在于 `ptysign.py` 与 `hap-sign-tool` 的进程内存，进程结束即消失。
- **关键点**：`hap-sign-tool` 用 JDK `Console.readPassword()` 读口令，
  而 `readPassword` 会丢弃「在它开始读之前就已经进入终端输入缓冲」的字符
  （type-ahead）。所以不能 `printf 'pwd\npwd\n' | script ...` 提前灌入——
  那样口令既会被回显，又会被丢弃，稳定报 `keystore password was incorrect`。
- `ptysign.py` 起一个 pty，**等提示真正打印出来后再写口令**，此时回显已关闭。

### 执行

```bash
cd harmony-app-template
bash signing/sign-release.sh \
  --p12 ~/keys/my_release.p12 \
  --cer signing/my_release.cer \
  --p7b signing/my_release_profileRelease.p7b \
  --alias my_release
```

脚本流程：

1. 校验 java / hap-sign-tool / p12 / cer / p7b / 未签名 HAP 是否存在
2. 签 HAP → `entry-default-signed.hap`
3. 签 APP → `<name>-default-signed.app`
4. `verify-app` 校验并导出证书链与 Profile 到 `signing/verify/`
5. 打印产物路径、大小、SHA-256

常用参数：`--deveco`（IDE 路径）、`--sign-alg`（默认 `SHA256withECDSA`）、
`--compat-version`（默认从 SDK 元数据读）、`--hap/--app/--out-dir`、`--no-verify`。

> 签名顺序：先 `assembleHap` 和 `assembleApp` 产出**未签名**包，再跑签名脚本。
> 上架只传签名后的 **`.app`**。

---

## 8. 上传与提交前自查清单

| 检查项 | 要求 | 怎么查 |
| --- | --- | --- |
| 包名 | 与 AGC 应用完全一致，创建后不可改 | `AppScope/app.json5` |
| versionCode | 每次提交**递增** | `AppScope/app.json5` |
| versionName | 与应用内「关于」一致 | `AppScope/app.json5` |
| 权限 | 与隐私政策声明一致；能不用就不用 | `grep requestPermissions entry/src/main/module.json5` |
| releaseType | **`Release`**，不能是 `Beta1` | 第 4 节命令 |
| 签名类型 | **发布证书 + 发布 Profile**，不是调试证书 | `verify-app` 输出 / AGC 证书类型 |
| 产物类型 | 上传 `.app`，不是 `.hap` | `ls build/outputs/default/*.app` |
| 签名校验 | `verify-app` 无失败 | `signing/verify/` 下的证书链 |
| 图标 | 216/1024，正方形，PNG ≤3 MB | 工程三处已同步 |
| 截图 | 3–10 张，1080×1920，9:16，≤5 MB | 第 9 节 |
| 隐私政策 | 公网 HTTPS URL，内容与实际一致 | AGC 隐私政策字段 |
| AI 功能声明 | 与实际功能一致 | `templates/ai-disclosure.md` |
| 分类/标签 | 与功能匹配，页面能保存 | AGC 发布页 |

### 提交后的状态流转（本次实测）

1. 点「提交审核」→ 弹纯信息确认框（无协议勾选、无补充材料）
2. 状态变为 **「预审中」**，页面提示预审约 **30–40 分钟**
3. 预审通过后自动转入 **「正在等待审核」**，即正式审核
4. 审核期间不能改包；被驳回需按意见修改并**递增 versionCode** 重新提交

---

## 9. 截图与素材

### 9.1 规格

| 项 | 要求 |
| --- | --- |
| 手机竖向截图 | 3–10 张，**9:16**，**1080×1920**，PNG/JPG ≤5 MB，不允许动图 |
| 平板竖向 | 2:3，1280×1920（单独在平板页签上传） |
| 图标 | 216×216 或 1024×1024，正方形，PNG ≤3 MB |

### 9.2 抓图 → 转商店规格

```bash
# 1) 从模拟器/真机抓原图（默认 screenshots/raw）
bash screenshots/capture-emulator.sh -o screenshots/raw -p 01_home

# 2) 批量转 1080×1920（等比缩放 + 左右补边）
python3 screenshots/make-store-shots.py screenshots/raw -o screenshots/store
```

### 9.3 为什么要补边，不直接裁

手机截图常见 1280×2832（约 9:20），比 9:16 更长。直接居中裁到 9:16 会切掉
顶部状态栏和底部导航栏；拉伸会变形。正确做法：

1. 按目标高度等比缩放（1280×2832 → 868×1920）；
2. 左右各补 `(1080-868)/2 = 106 px`。

`make-store-shots.py` 支持两种补边：

- `--pad edge`（默认）：取每行最左/最右 1px 横向拉伸，和页面底色/系统栏自然接缝；
- `--pad solid --bg "#0B0C10"`：纯色填充，适合纯色背景。

> 参数化：`--width/--height` 可改成平板 1280×1920；
> 非 9:16 会给出提示但仍执行。

---

## 10. 可复用文本模板

| 文件 | 内容 |
| --- | --- |
| [`templates/privacy-policy.md`](templates/privacy-policy.md) | 隐私政策全文，含「不收集任何信息」「无权限」「无第三方 SDK」写法，`【】`占位 |
| [`templates/ai-disclosure.md`](templates/ai-disclosure.md) | AI 功能声明的判断口径、选「不涉及」时的说明文案、涉及 AI 时的必填清单 |
| [`templates/store-listing.md`](templates/store-listing.md) | 应用名长度、简介字数、介绍结构、截图/图标规格、提交前物料自检 |

---

## 11. 错误原文 → 原因 → 解法

以下 9 条都是本次从建工程到提审真实遇到过的（原文照抄，未改写）。

| # | 错误原文 | 场景 | 原因 | 解法 |
| --- | --- | --- | --- | --- |
| 1 | `api version parameter is illegal! Expected format <major>[.<minor>][.<patch>]!` | 编译 | `compatibleSdkVersion` 用了旧格式 `"5.0.0(12)"` | 改成点分 platformVersion：`compileSdkVersion/compatibleSdkVersion/targetSdkVersion` = `"26.0.0"` |
| 2 | `Error Message: Hvigor config file .../hvigor/hvigor-config.json5 does not exist.` | 执行 hvigorw | 在工程**父目录**执行，hvigor 找不到 `hvigor/hvigor-config.json5` | `cd` 到工程根（含 `hvigorfile.ts` 的那一层）再执行 |
| 3 | `Property 'tabIndex' in type 'Index' is not assignable to the same property in base type 'CustomComponent'` | 编译 ArkTS | `@State tabIndex` 与 `CustomComponent` 内置属性同名 | 状态变量改名（如 `currentTab`），避开组件基类内置属性 |
| 4 | `WARN: No signingConfig found for product default` | 编译 | 工程没配 `signingConfigs`（模板故意不配） | 只跑模拟器可忽略；上架走 `signing/sign-release.sh`，不要为了消警告把口令写进配置 |
| 5 | `keystore password was incorrect` | 签名 | 用 `printf 'pwd\npwd\n' \| script ...` 提前灌口令：口令被 pty 回显，且被 `Console.readPassword()` 当 type-ahead 丢弃 | 用 `ptysign.py` 等提示打印后再写口令（本模板已内置） |
| 6 | `上传的CSR文件无效` | AGC 新增证书 | CSR 用 RSA 生成；HarmonyOS 要求 EC + `SHA256withECDSA` | 重新生成 EC 密钥库与 CSR：`-keyalg EC -groupname secp384r1 -sigalg SHA256withECDSA`；换 CSR 必须同时换 p12 |
| 7 | `获取上传地址失败` | 华为上传组件 | 登录态过期/前端状态异常 | 刷新页面重试**一次**；跳登录页就手动登录，仍失败则停止并反馈页面提示与截图，不要反复刷 |
| 8 | `上传失败` | 华为上传组件 | 上传包内文件名含下划线等特殊字符，或前端状态异常 | 压缩包内文件名改为纯中文+数字；刷新页面后重传（本次同时遇到「服务端已收到但页面不回显」的前端 bug，可按文件大小/时间线核实） |
| 9 | `"releaseType": "Beta1"`（`pack.info` 原文；AGC 预审/审核会因此驳回） | 出包自查 | 用了 Beta 版 DevEco Studio / Beta SDK（26.0.1.290 / SDK 26.0.1.120） | 换 Release 版 IDE（26.0.0.865 / SDK 26.0.0.105）重打，确认 `apiVersion.releaseType` 为 `Release` 后再上传 |

> 第 9 条是本次**在提交前自查发现并拦下**的问题：Beta 包已上传过一次，
> 随后用 Release 工具链重打、替换，未真正收到驳回意见。审核驳回文案以 AGC 实际提示为准。

---

## 12. 本模板的编译验证记录（2026-11-12）

用 `~/Applications/DevEco-Studio-26.0.0.app`（Release，26.0.0.865 / SDK 26.0.0.105）
在本仓根目录实测，**未改包名、未改版本**（模板本身就是 `com.example.template` / `26.0.0`）：

```text
$ hvigorw clean --no-daemon
> hvigor Finished :entry:clean... after 1 ms
> hvigor BUILD SUCCESSFUL in 1 s 249 ms
2 tasks in total: 2 executed, 0 up-to-date

$ hvigorw --mode module -p product=default assembleHap --no-daemon
> hvigor Finished :entry:default@CompileArkTS... after 1 s 686 ms
> hvigor Finished :entry:default@PackageHap... after 796 ms
> hvigor WARN: No signingConfig found for product default
> hvigor Finished :entry:assembleHap... after 1 ms
> hvigor BUILD SUCCESSFUL in 4 s 969 ms
33 tasks in total: 33 executed, 0 up-to-date
```

产物：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap   22,774 bytes
build/outputs/default/harmony-app-template-default-unsigned.app   8,327 bytes
```

`pack.info` 自查：

```text
apiVersion.releaseType = Release
app.apiReleaseType     = None（未签名 .app 中未出现，正常；以 apiVersion.releaseType 为准）
```

`assembleApp` 同样通过：

```text
> hvigor Finished ::PackageApp... after 454 ms
> hvigor WARN: No signingConfig found for product default
> hvigor BUILD SUCCESSFUL in 5 s 89 ms
42 tasks in total: 31 executed, 11 up-to-date
```

> 说明：`WARN: No signingConfig found` 是模板不配置签名的预期结果；
> 未签名 HAP 可直接装模拟器，上架包用签名脚本处理。

---

## 13. 合规与维护提醒

- **包名**：AGC 创建后不可改，动手前先定好；改名等于新建应用。
- **版本号**：每次提交 `versionCode` 必须递增，否则 AGC 拒收。
- **权限**：模板零权限。新增任何权限都要同步隐私政策 + AGC 隐私标签 + AI/数据安全表单。
- **证书**：AGC 签发有效期 3 年；`.p12` 和口令分开保管并备份，丢失只能重签。
- **素材版权**：AI 生成素材需确认商用授权并按要求披露；正式上架前替换占位图。
- **安全**：本仓 `.gitignore` 已排除 `*.p12/*.cer/*.p7b/*.csr`。提交前再跑一次
  `git status`，确认没有把签名材料带进版本库。
