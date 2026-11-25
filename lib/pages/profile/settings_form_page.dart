import 'package:flutter/material.dart';

import 'ucenter_view_page.dart';

/// 一个基本设置页的描述。
///
/// 2026-11-25 网站改版后，设置页的字段结构与当前值都改成 Vue 单页应用里
/// 硬编码 + `shezhi_fun.php?type=formget` 的扁平 `meta`，旧 `views/Shezhi_*.php`
/// 表单片段已整体移除。原生复刻每个字段的成本高、网站再改一次又会失效，
/// 所以这里统一用内置 WebView 打开网站的对应路由（登录 Cookie 会同步过去）。
class UcenterSettingsSpec {
  /// 用户中心的哈希路由，如 `Shezhi_jiben`。
  final String route;

  /// 保存用的 `shezhi_fun.php?type=<type>`（保留给后续原生化时使用）。
  final String type;

  final String title;

  /// 入口页里的一行说明。
  final String description;

  const UcenterSettingsSpec({
    required this.route,
    required this.type,
    required this.title,
    this.description = '',
  });
}

/// 基本设置入口（浏览 / 顶部导航 / 摸鱼 / 自定义 CSS / 自定义 JS）。
///
/// 新版把「实时线报设置」并进了浏览设置，原来的 `Shezhi_shishi` 已不在菜单里。
const Map<String, UcenterSettingsSpec> ucenterSettingsSpecs = {
  'jiben': UcenterSettingsSpec(
    route: 'Shezhi_jiben',
    type: 'jiben_liulan',
    title: '优化浏览设置',
    description: '标题标红、分页方式、新标签页',
  ),
  'daohang': UcenterSettingsSpec(
    route: 'Shezhi_daohang',
    type: 'jiben_daohang',
    title: '顶部导航设置',
    description: '电脑端 / 手机端顶部导航',
  ),
  'moyu': UcenterSettingsSpec(
    route: 'Shezhi_moyu',
    type: 'jiben_moyu',
    title: '优化摸鱼设置',
    description: '伪装标题、图标与轮换',
  ),
  'css': UcenterSettingsSpec(
    route: 'Shezhi_css',
    type: 'jiben_css',
    title: '自定义 CSS 样式',
    description: '自定义 CSS 样式',
  ),
  'js': UcenterSettingsSpec(
    route: 'Shezhi_js',
    type: 'jiben_js',
    title: '自定义 JS 脚本',
    description: '自定义 JS 脚本',
  ),
  // 商品转链（同一套 shezhi_fun.php 表单，字段是各平台的密钥与格式）
  'zhuanlian_taobao': UcenterSettingsSpec(
    route: 'Shezhi_zhuanlian',
    type: 'zhuanlian_taobao',
    title: '淘宝转链设置',
    description: 'AppKey / AppSecret / PID 与链接格式',
  ),
  'zhuanlian_jingdong': UcenterSettingsSpec(
    route: 'ZhuanlianJd',
    type: 'zhuanlian_jingdong',
    title: '京东转链设置',
    description: '联盟 unionId / positionId 与链接格式',
  ),
  'zhuanlian_pinduoduo': UcenterSettingsSpec(
    route: 'ZhuanlianPdd',
    type: 'zhuanlian_pinduoduo',
    title: '拼多多转链设置',
    description: 'AppKey / AppSecret / PID 与链接格式',
  ),
};

/// 基本设置入口。
const List<String> ucenterBasicSettingsKeys = [
  'jiben',
  'daohang',
  'moyu',
  'css',
  'js',
];

/// 商品转链的三个平台。
const List<String> ucenterTransferKeys = [
  'zhuanlian_taobao',
  'zhuanlian_jingdong',
  'zhuanlian_pinduoduo',
];

/// 基本设置页：用内置 WebView 打开网站对应路由。
class SettingsFormPage extends StatelessWidget {
  final UcenterSettingsSpec spec;

  const SettingsFormPage({super.key, required this.spec});

  @override
  Widget build(BuildContext context) =>
      UcenterViewPage(route: spec.route, title: spec.title);
}
