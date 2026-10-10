import 'dart:async';

import 'package:flutter/material.dart';

/// 在屏幕中间弹一条提示，[duration] 后自动消失，点一下也能收起。
///
/// 仿网站 `layer.alert` 的居中提示（首页签到失败这类需要让用户看见、又不该打断
/// 操作的场合）。提示挂在根 Overlay 上，不依赖调用方所在的页面树。
void showCenterTip(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null || message.trim().isEmpty) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _CenterTip(
      message: message,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _CenterTip extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  const _CenterTip({
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_CenterTip> createState() => _CenterTipState();
}

class _CenterTipState extends State<_CenterTip> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
      _timer = Timer(widget.duration, _dismiss);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _visible = false);
    // 淡出动画播完再摘掉 Overlay。
    Timer(const Duration(milliseconds: 140), () {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 140),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
