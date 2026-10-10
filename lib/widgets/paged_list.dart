import 'package:flutter/material.dart';

import '../utils/error_message.dart';
import 'load_error_view.dart';

/// 取第 [page] 页（从 1 开始）的数据，连同总数返回。
typedef PageLoader<T> =
    Future<({List<T> items, int total})> Function(int page, int limit);

/// 分页列表的外部控制柄：外部事件（取消收藏、删除评论）后刷新或就地移除一行。
class PagedListController<T> extends ChangeNotifier {
  _PagedListState<T>? _state;

  void _attach(_PagedListState<T> state) => _state = state;
  void _detach(_PagedListState<T> state) {
    if (identical(_state, state)) _state = null;
  }

  /// 从第一页重新加载。
  void reload() => _state?.reload();

  /// 就地移除已删除的行（避免整页刷新导致滚动位置丢失）。
  void removeWhere(bool Function(T item) test) => _state?.removeWhere(test);
}

/// 触底加载的分页列表，收藏页与用户中心各列表页共用。
///
/// 骨架取自原来的收藏页：首屏加载 → 错误态（[LoadErrorView]）/空态 → 下拉刷新 +
/// 触底自动加载下一页。
class PagedList<T> extends StatefulWidget {
  final PageLoader<T> loader;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String emptyText;
  final int pageSize;
  final PagedListController<T>? controller;
  final EdgeInsetsGeometry padding;

  const PagedList({
    super.key,
    required this.loader,
    required this.itemBuilder,
    required this.emptyText,
    this.pageSize = 20,
    this.controller,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  State<PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<PagedList<T>> {
  final List<T> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _page = 1;
  int _total = 0;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    reload();
  }

  @override
  void didUpdateWidget(covariant PagedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  Future<void> reload() => _load(reset: true);

  void removeWhere(bool Function(T item) test) {
    if (!mounted) return;
    setState(() {
      final removed = _items.where(test).length;
      _items.removeWhere(test);
      _total = (_total - removed).clamp(0, 1 << 31);
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = reset ? 1 : _page + 1;
      final result = await widget.loader(page, widget.pageSize);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
        } else {
          _items.addAll(result.items);
        }
        _page = page;
        _total = result.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return LoadErrorView(message: _error!, onRetry: reload);
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          widget.emptyText,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.separated(
        padding: widget.padding,
        itemCount: _items.length + (_hasMore || _loadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            if (!_loadingMore) {
              // Trigger load more once footer is built.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _load(reset: false);
              });
            }
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return widget.itemBuilder(context, _items[index], index);
        },
      ),
    );
  }
}
