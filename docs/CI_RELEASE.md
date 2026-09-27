# CI / 自动发版与 Android 签名

## 发版方式（tag 驱动）

推送到 `main` **不再自动发版**，正式发版必须打 tag：

```bash
git tag v1.5.0
git push origin v1.5.0
```

| 触发 | 结果 |
|------|------|
| `push` tag（形如 `v1.5.0`） | 签名编译 → 公开 Release（挂在该 tag 上）→ 回写版本号 |
| `push` 到 `main` | 只发代码，不编译、不发版 |
| 手动 `workflow_dispatch` | 同上，但 ref 下拉框里必须选择已存在的 `vX.Y.Z` tag |

约束：

- tag 名即版本号：`v1.5.0` → versionName `1.5.0`（必须是 `vX.Y.Z` 三位数字形式）
- tag 必须打在 `main` 的提交上；若不在 `main` 上，Release 仍会发布，但会跳过版本号回写（job 里给出 warning）
- 不允许降级发版：tag 版本低于 `publish/version.json` 里已发布的版本时直接失败

版本策略：

对外版本号仅为 **versionName**（1.5.0），不含 +数字，便于客户端检测更新。

- `versionCode` = `max(pubspec 旧值+1, github.run_number)`，保证单调递增
- Release 发布后回写仓库：`chore: bump version to x.y.z [skip ci]`（pubspec 内部仍写 `x.y.z+code` 供 Android versionCode 使用）

产物命名：

- `xianbao-v{versionName}-armv8-release.apk`（真机推荐，如 `xianbao-v1.5.0-armv8-release.apk`）
- `...-armv7-release.apk`
- `...-x86_64-release.apk`

---

## 必填 GitHub Secrets

仓库 → **Settings → Secrets and variables → Actions → New repository secret**

| Secret 名 | 说明 |
|-----------|------|
| `ANDROID_KEYSTORE_BASE64` | `.jks` / `.keystore` 文件的 Base64 全文 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名（alias） |
| `ANDROID_KEY_PASSWORD` | 密钥密码（可与 store 密码相同） |

### 生成 Base64（Windows PowerShell）

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("D:\path\to\your-upload-key.jks")
) | Set-Clipboard
```

粘贴到 Secret `ANDROID_KEYSTORE_BASE64`（单行、无换行）。

### 生成 Base64（Linux / macOS）

```bash
base64 -w0 your-upload-key.jks | pbcopy   # macOS
base64 -w0 your-upload-key.jks            # Linux，复制输出
```

---

## 本地 release 签名（可选）

1. 将 keystore 放到 `android/app/upload-keystore.jks`（不要提交）
2. 创建 `android/key.properties`（不要提交）：

```properties
storePassword=你的store密码
keyPassword=你的key密码
keyAlias=你的alias
storeFile=upload-keystore.jks
```

3. 构建：

```bash
flutter build apk --release --split-per-abi
```

无 `key.properties` 时 release 会回退为 **debug 签名**（仅便于本地调试）。

---

## 首次启用检查清单

1. 四个 Secrets 已配置  
2. 仓库已开启 Actions  
3. `main` 保护规则如开启，需允许 `github-actions[bot]` 推送版本 commit（或关闭对 bot 的限制）  
4. 在 `main` 上打一个 `vX.Y.Z` tag 并推送

---

## 常见问题

**Release 失败：Missing secret**  
→ Secrets 名称必须与上表完全一致。

**安装提示签名冲突**  
→ 以前 debug 签名的包需先卸载，再装正式签名包。

**推送 main 没有触发构建**  
→ 预期行为。发版只认 tag，见上文「发版方式」。

**tag 已存在 / 想重新发同一个版本**  
→ 删掉远程 tag 后重推，或在 Actions 里手动 Run workflow 并选择该 tag（版本号相同是允许的，只有降级会被拒绝）。

**报错「tag 版本低于已发布的 x.y.z」**  
→ tag 名比 `publish/version.json` 里的版本旧。改用更高的版本号。

---

## 客户端检测更新

对齐 lx-music：客户端读取仓库内 `publish/version.json`（不含 `+build` 的 versionName）。

| 镜像（按顺序尝试） | URL |
|--------------------|-----|
| GitHub raw | `https://raw.githubusercontent.com/cdnsr/xianbao/main/publish/version.json` |
| jsDelivr | `https://cdn.jsdelivr.net/gh/cdnsr/xianbao@main/publish/version.json` |
| fastly / gcore | 同上 host 前缀 |

结构示例：

```json
{
  "version": "1.4.10",
  "desc": "更新说明",
  "history": [{ "version": "1.4.9", "desc": "…" }]
}
```

发版时 CI 会与 `pubspec.yaml` 一并回写 `publish/version.json`。

APK 下载：

```
https://github.com/cdnsr/xianbao/releases/download/v{version}/xianbao-v{version}-{armv8|armv7|x86_64}-release.apk
```

App 行为：

- 启动约 2 秒后静默检查；有新版本且未忽略则弹窗
- 登录页 / 用户中心 AppBar「检查更新」可手动检查
- 支持忽略此版本、历史更新说明、应用内下载并调起安装
