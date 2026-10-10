import 'dart:async';

import 'package:flutter/material.dart';

/// 头像弹出菜单的一项。
class AvatarMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AvatarMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// 在头像下方弹出菜单（纵向排列），未点击时 [autoClose] 后自动关闭。
///
/// 用 Overlay 而不是 `showMenu`：需要「不点也自动收」＋「点外部收起」，
/// 并且要能按头像位置贴边对齐。
void showAvatarMenu(
  BuildContext context, {
  required Rect anchor,
  required List<AvatarMenuItem> items,
  Duration autoClose = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AvatarMenuOverlay(
      anchor: anchor,
      items: items,
      autoClose: autoClose,
      onDismissed: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _AvatarMenuOverlay extends StatefulWidget {
  final Rect anchor;
  final List<AvatarMenuItem> items;
  final Duration autoClose;
  final VoidCallback onDismissed;

  const _AvatarMenuOverlay({
    required this.anchor,
    required this.items,
    required this.autoClose,
    required this.onDismissed,
  });

  @override
  State<_AvatarMenuOverlay> createState() => _AvatarMenuOverlayState();
}

class _AvatarMenuOverlayState extends State<_AvatarMenuOverlay> {
  Timer? _autoCloseTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
      _autoCloseTimer = Timer(widget.autoClose, _dismiss);
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _autoCloseTimer?.cancel();
    if (!mounted) return;
    setState(() => _visible = false);
    // 让淡出动画播完再移除 Overlay。
    Timer(const Duration(milliseconds: 120), () {
      if (mounted) widget.onDismissed();
    });
  }

  void _select(AvatarMenuItem item) {
    _autoCloseTimer?.cancel();
    // 先收起菜单，再执行动作（动作里通常会 push 新页面）。
    widget.onDismissed();
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    const width = 168.0;
    const itemHeight = 44.0;
    final height = widget.items.length * itemHeight + 8;

    // 贴着头像下沿居中展开；越界时往回收，保证整块菜单都在屏幕内。
    final top = widget.anchor.bottom + 6;
    var left = widget.anchor.center.dx - width / 2;
    left = left.clamp(8.0, media.size.width - width - 8);
    final maxTop = media.size.height - height - 8;
    final clampedTop = top.clamp(8.0, maxTop < 8 ? 8.0 : maxTop);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: clampedTop,
          width: width,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: Material(
              color: theme.colorScheme.surface,
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in widget.items)
                      InkWell(
                        onTap: () => _select(item),
                        child: SizedBox(
                          height: itemHeight,
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              Icon(
                                item.icon,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                item.label,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
