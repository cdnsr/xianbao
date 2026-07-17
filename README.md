# 线报酷 (xianbao)

Flutter 客户端，封装 [new.xianbao.fun](https://new.xianbao.fun) 线报内容，提供更接近原生的移动端体验。

## 功能

- 首页文章列表（原生 Flutter，分页 / 缓存 / 下拉刷新）
- 搜索、文章详情（正文 + 评论）
- 登录 / 用户中心（WebView + Cookie 共享）
- 收藏管理
- 深色模式（含登录 / 用户中心 WebView）

## 环境

- Flutter stable（项目基于 Flutter 3.x / Dart 3.x）
- Android SDK（本地 `android/local.properties` 自行配置，勿提交）

## 运行

```bash
flutter pub get
flutter run
```

## 构建 APK

```bash
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`（已在 `.gitignore` 中忽略 `build/`）。

## 说明

- 无网站后台权限，仅基于公开网页 / 接口封装，不修改服务端。
- 接口与页面结构分析见 `API_ANALYSIS.md`。
- **请勿提交** Cookie、密钥、`local.properties`、登录会话等敏感文件。
