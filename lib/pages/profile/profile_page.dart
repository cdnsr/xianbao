import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/ucenter.dart';
import '../../services/app_state.dart';
import '../../services/ucenter_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/remote_image.dart';
import '../collect/collect_list_page.dart';
import 'avatar_menu.dart';
import 'avatar_picker_page.dart';
import 'binding_page.dart';
import 'filter_settings_page.dart';
import 'follow_settings_page.dart';
import 'password_page.dart';
import 'profile_edit_page.dart';
import 'settings_hub_page.dart';
import 'soon_page.dart';
import 'spend_page.dart';
import 'ucenter_list_page.dart';

/// 用户中心（原生，替代原来的 WebView 页面）。
///
/// 数据来自网站用户中心的两个服务端片段：`views/index.php`（等级/积分/收藏/评论
/// 统计）与 `views/Nav.php`（头像、昵称、等级标识）。
class ProfilePage extends StatefulWidget {
  final AppState appState;

  const ProfilePage({super.key, required this.appState});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final UcenterService _service = UcenterService();
  final GlobalKey _avatarKey = GlobalKey();

  UcenterHome _home = UcenterHome.empty;
  UcenterProfile _profile = UcenterProfile.empty;
  bool _loading = true;
  String? _error;

  int _lastLoginVersion = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final version = widget.appState.loginVersion;
    if (_lastLoginVersion != version) {
      final first = _lastLoginVersion < 0;
      _lastLoginVersion = version;
      if (!first) _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _service.fetchHome(),
        _service.fetchProfile(),
      ]);
      if (!mounted) return;
      final home = results[0] as UcenterHome;
      if (home.sessionExpired) {
        // 会话过期：提示，并让 AppState 重新判定登录态（第三个 Tab 会切回登录页）。
        setState(() {
          _home = home;
          _profile = UcenterProfile.empty;
          _loading = false;
          _error = kUcenterSessionExpiredMessage;
        });
        unawaited(widget.appState.refreshLoginState());
        return;
      }
      setState(() {
        _home = home;
        _profile = results[1] as UcenterProfile;
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

  void _openAvatarMenu() {
    final box = _avatarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    showAvatarMenu(
      context,
      anchor: origin & box.size,
      items: [
        AvatarMenuItem(
          icon: Icons.face_retouching_natural_outlined,
          label: '修改图像',
          onTap: () => _push(const AvatarPickerPage(), reload: true),
        ),
        AvatarMenuItem(
          icon: Icons.badge_outlined,
          label: '基本资料',
          onTap: () => _push(const ProfileEditPage(), reload: true),
        ),
        AvatarMenuItem(
          icon: Icons.verified_user_outlined,
          label: '认证绑定',
          onTap: () => _push(const BindingPage()),
        ),
        AvatarMenuItem(
          icon: Icons.password_outlined,
          label: '重置密码',
          onTap: () => _push(const PasswordPage()),
        ),
        AvatarMenuItem(
          icon: Icons.logout,
          label: '注销登陆',
          onTap: _confirmLogout,
        ),
      ],
    );
  }

  Future<void> _push(Widget page, {bool reload = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (reload && mounted) await _load();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注销登陆'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await widget.appState.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户中心'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _home.stats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _home.stats.isEmpty) {
      // 下拉刷新需要 ListView 才能工作，错误态也放进可滚动容器。
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
        _buildHeader(Theme.of(context)),
        _buildStats(Theme.of(context)),
        _buildMenuGrid(Theme.of(context)),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final levelText = _profile.levelText.isNotEmpty
        ? _profile.levelText
        : _home.level;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        children: [
          GestureDetector(
            onTap: _openAvatarMenu,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  key: _avatarKey,
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primaryContainer,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _profile.avatarUrl.isEmpty
                      ? Icon(
                          Icons.person,
                          size: 44,
                          color: theme.colorScheme.onPrimaryContainer,
                        )
                      : RemoteImage(
                          url: _profile.avatarUrl,
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                ),
                // 小箭头提示头像可点开菜单。
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface,
                  ),
                  child: Icon(
                    Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _profile.nickname.isEmpty ? '线报酷用户' : _profile.nickname,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (levelText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                levelText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStats(ThemeData theme) {
    final items = <({String label, String value, VoidCallback onTap})>[
      (label: '等级', value: _home.level, onTap: _openSpend),
      (label: '积分', value: _home.points, onTap: _openSpend),
      (label: '收藏', value: _home.collects, onTap: _openCollect),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: item.onTap,
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(
                      children: [
                        Text(
                          item.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.value.isEmpty ? '—' : item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid(ThemeData theme) {
    final entries = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.favorite_border,
        label: '我的关注',
        onTap: () => _push(const FollowSettingsPage()),
      ),
      (
        icon: Icons.tune,
        label: '基本设置',
        onTap: () => _push(const SettingsHubPage()),
      ),
      (
        icon: Icons.notifications_active_outlined,
        label: '推送设置',
        onTap: () => _push(const PushSettingsSoonPage()),
      ),
      (
        icon: Icons.filter_alt_outlined,
        label: '筛选设置',
        onTap: () => _push(const FilterSettingsPage()),
      ),
      (
        icon: Icons.link,
        label: '商品转链',
        onTap: () => _push(const TransferSettingsSoonPage()),
      ),
      (
        icon: Icons.support_agent_outlined,
        label: '工单系统',
        onTap: () => _push(
          const UcenterListPage(specKey: 'tickets'),
        ),
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: '消费管理',
        onTap: _openSpend,
      ),
      (
        icon: Icons.mode_comment_outlined,
        label: '评论管理',
        onTap: () => _push(
          const UcenterListPage(specKey: 'comments'),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          for (var row = 0; row < entries.length; row += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (var i = row; i < row + 2 && i < entries.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _buildMenuTile(theme, entries[i]),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(
    ThemeData theme,
    ({IconData icon, String label, VoidCallback onTap}) entry,
  ) {
    return InkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          children: [
            Icon(entry.icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.label,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  void _openSpend() => _push(const SpendPage());

  void _openCollect() =>
      _push(const CollectListPage(), reload: true);
}
