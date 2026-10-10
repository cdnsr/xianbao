import 'package:flutter/material.dart';

import '../../models/ucenter.dart';
import '../../models/ucenter_table.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../utils/external_link.dart';
import '../../widgets/load_error_view.dart';
import 'ucenter_list_page.dart';

/// 消费管理：积分 / 会员等级概览 + 充值、订单、流水入口。
///
/// 充值与购买会员涉及第三方支付，App 内只做展示，点按钮用系统浏览器打开网站
/// 对应页面完成支付（回跳、卡密、支付宝/微信都在网站那边）。
class SpendPage extends StatefulWidget {
  const SpendPage({super.key});

  @override
  State<SpendPage> createState() => _SpendPageState();
}

class _SpendPageState extends State<SpendPage> {
  final UcenterService _service = UcenterService();
  UcenterHome _home = UcenterHome.empty;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final home = await _service.fetchHome();
      if (!mounted) return;
      setState(() {
        _home = home;
        _loading = false;
        _error = home.sessionExpired ? kUcenterSessionExpiredMessage : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('消费管理'), centerTitle: true),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_loading && _home.stats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _home.stats.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: LoadErrorView(message: _error!, onRetry: _load),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              _buildBalanceCard(theme, '积分', _home.points),
              const SizedBox(width: 8),
              _buildBalanceCard(theme, '会员等级', _home.level),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _buildSection(theme, '充值', [
          (
            label: '积分充值',
            icon: Icons.add_card_outlined,
            onTap: () => openUcenterPage('Pay'),
          ),
          (
            label: '购买 / 升级会员',
            icon: Icons.workspace_premium_outlined,
            onTap: () => openUcenterPage('Vip'),
          ),
        ]),
        _buildSection(theme, '记录', [
          (
            label: '已购订单',
            icon: Icons.receipt_long_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UcenterListPage(specKey: 'orders'),
              ),
            ),
          ),
          (
            label: '流水账单',
            icon: Icons.list_alt_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LiuShuiPage()),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '充值与会员购买需要第三方支付，会打开网站页面完成。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(ThemeData theme, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value.isEmpty ? '—' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    List<({String label, IconData icon, VoidCallback onTap})> entries,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      entries[i].icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(entries[i].label),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: entries[i].onTap,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 流水账单：服务端 HTML 表格（`views/Liushuilist.php`），解析成原生列表展示。
class LiuShuiPage extends StatefulWidget {
  const LiuShuiPage({super.key});

  @override
  State<LiuShuiPage> createState() => _LiuShuiPageState();
}

class _LiuShuiPageState extends State<LiuShuiPage> {
  final UcenterService _service = UcenterService();
  List<UcenterFragmentTable> _tables = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await _service.fetchFragmentTables('Liushuilist');
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('流水账单'), centerTitle: true),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: LoadErrorView(message: _error!, onRetry: _load),
          ),
        ],
      );
    }
    final visible = _tables.where((t) => !t.isEmpty).toList();
    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              '暂无流水记录',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final table in visible) ...[
          if (table.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                table.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          for (final row in table.rows)
            _buildRow(theme, table.headers, row),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRow(ThemeData theme, List<String> headers, List<String> row) {
    // 首列当主文案，其余按「表头：值」展示；列数不齐时按实际对齐。
    final title = row.isNotEmpty ? row.first : '';
    final details = <String>[];
    for (var i = 1; i < row.length && i < headers.length; i++) {
      if (row[i].isEmpty) continue;
      details.add('${headers[i]}：${row[i]}');
    }
    return Container(
      color: theme.colorScheme.surface,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyMedium),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final detail in details)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
