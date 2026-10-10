import 'package:flutter/material.dart';

import '../../utils/external_link.dart';

/// 一个下一轮才原生化、目前先给出入口的菜单项。
class SoonEntry {
  final String label;
  final String description;

  /// 网站用户中心里的哈希路由（`/Ucenter#/<route>`）。
  final String route;

  const SoonEntry({
    required this.label,
    required this.description,
    required this.route,
  });
}

/// 「本轮暂未支持」的入口页。
///
/// 列清楚这一组下面有哪些子页（与网站用户中心一致），点进去用系统浏览器打开网站
/// 对应页面，等下一轮原生化后再替换成本地页面。
class SoonPage extends StatelessWidget {
  final String title;
  final String note;
  final List<SoonEntry> entries;

  const SoonPage({
    super.key,
    required this.title,
    required this.note,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本轮暂未原生化：$note。点下面的条目会用浏览器打开网站对应页面。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final entry in entries)
            ListTile(
              title: Text(entry.label),
              subtitle: entry.description.isEmpty
                  ? null
                  : Text(entry.description),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openUcenterPage(entry.route),
            ),
        ],
      ),
    );
  }
}

/// 推送设置（独立插件 xbpush，渠道/规则/日志，下一轮原生化）。
class PushSettingsSoonPage extends SoonPage {
  const PushSettingsSoonPage({super.key})
    : super(
        title: '推送设置',
        note: '推送渠道 / 推送规则 / 推送日志 / 历史推送数据',
        entries: const [
          SoonEntry(
            label: '推送渠道',
            description: 'Bark、钉钉、企业微信等 19 种渠道的配置',
            route: 'Shezhi_tuisong',
          ),
          SoonEntry(
            label: '推送规则',
            description: '推什么内容、发到哪些渠道',
            route: 'TuisongRule',
          ),
          SoonEntry(
            label: '推送日志',
            description: '最近 14 天的推送记录与失败原因',
            route: 'TuisongLog',
          ),
          SoonEntry(
            label: '历史推送数据查看',
            description: '旧版推送配置迁移',
            route: 'TuisongHistory',
          ),
        ],
      );
}

/// 商品转链（三家平台的密钥与链接格式，下一轮原生化）。
class TransferSettingsSoonPage extends SoonPage {
  const TransferSettingsSoonPage({super.key})
    : super(
        title: '商品转链',
        note: '淘宝转链 / 京东转链 / 拼多多转链',
        entries: const [
          SoonEntry(
            label: '淘宝转链设置',
            description: 'AppKey / AppSecret / PID 与商品、活动链接格式',
            route: 'Shezhi_zhuanlian',
          ),
          SoonEntry(
            label: '京东转链设置',
            description: '联盟 unionId / positionId 与链接格式',
            route: 'ZhuanlianJd',
          ),
          SoonEntry(
            label: '拼多多转链设置',
            description: 'AppKey / AppSecret / PID 与链接格式',
            route: 'ZhuanlianPdd',
          ),
        ],
      );
}
