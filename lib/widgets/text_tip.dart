import 'dart:async';

import 'package:flutter/material.dart';

/// 轻量文字提示：页面下方一行纯文字，[duration] 后自动淡出。
///
/// 用户中心的「已保存 / 已删除」这类操作回执用它——只是一行字，不要 Material
/// SnackBar 那种带背景色的条幅；默认 1 秒，短到不挡内容。失败提示可以传更长的
/// 时长（见 `errorDuration`），但样式保持一致。
///
/// 提示挂在根 Overlay 上、不拦截点击（`IgnorePointer`），所以它下面的列表照样能滑。
void showTextTip(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 1),
}) {
  final text = message.trim();
  if (text.isEmpty) return;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TextTip(
      message: text,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

/// 失败提示用的时长：比成功回执长一点，够看清原因。
const Duration kErrorTipDuration = Duration(seconds: 3);

class _TextTip extends StatefulWidget {
  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  const _TextTip({
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_TextTip> createState() => _TextTipState();
}

class _TextTipState extends State<_TextTip> {
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
    Timer(const Duration(milliseconds: 160), () {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: 24,
            right: 24,
            // 让开底部安全区与底部导航栏（有导航栏时约 56）。
            bottom: media.viewPadding.bottom + 72,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.4,
                  // 只有文字，靠一点阴影在深浅色下都看得清。
                  shadows: const [
                    Shadow(color: Color(0x99000000), blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
