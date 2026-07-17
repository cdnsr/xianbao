# CI / 自动发版与 Android 签名

## 行为摘要

| 触发 | 结果 |
|------|------|
| `push` 到 `main`（提交说明不含 `[skip ci]`） | 自动升版本 → 签名编译 → 公开 Release |
| 手动 `workflow_dispatch` | 同上 |
| 仅改 `*.md` / `docs/**` | 不触发 |
| 版本回写提交（带 `[skip ci]`） | 不触发二次构建 |

版本策略（方案 B）：

- 每次发版将 `pubspec.yaml` 的 **patch +1**（如 `1.4.7` → `1.4.8`）
- `versionCode` = `max(旧值+1, github.run_number)`，保证单调递增
- 回写仓库：`chore: bump version to x.y.z+N [skip ci]`

产物命名：

- `xianbao-v{versionName}+{versionCode}-armv8-release.apk`（真机推荐）
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
4. 向 `main` 推送一次业务改动，或手动 Run workflow  

---

## 常见问题

**Release 失败：Missing secret**  
→ Secrets 名称必须与上表完全一致。

**安装提示签名冲突**  
→ 以前 debug 签名的包需先卸载，再装正式签名包。

**版本 commit 导致循环构建**  
→ 已用 `[skip ci]` + job `if` 双重防护。

**tag 已存在**  
→ 每次 patch 与 versionCode 递增，一般不会冲突；若手动删 tag 后重跑，注意勿复用相同 tag。
