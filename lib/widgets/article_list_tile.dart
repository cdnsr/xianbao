import 'package:flutter/material.dart';
import '../models/article.dart';
import '../theme/app_theme.dart';

/// One article row, styled after the website's `li.article-list` on mobile:
///
///   [category icon] [title .....................] [replies] [time]
///
/// Mirrors `.article-list` / `.article-list .figure` / `.article-list .badge`
/// from the site stylesheet.
class ArticleListTile extends StatelessWidget {
  final ArticleListItem article;
  final VoidCallback onTap;

  /// Draws the trailing hairline between rows. The last row of a list can
  /// pass false so it does not double up with the pagination area.
  final bool showDivider;

  const ArticleListTile({
    super.key,
    required this.article,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timeText = _shortTime(article);
    final figure = article.figureAsset;

    final badgeBg = isDark ? AppPalette.darkBadge : AppPalette.lightBadge;
    final badgeFg = isDark ? AppPalette.darkTimeText : AppPalette.lightText;
    final timeFg = isDark ? AppPalette.darkTimeText : AppPalette.lightTimeText;

    return DecoratedBox(
      decoration: BoxDecoration(
        // `.sb` module background; rows sit on white / #2b333e like the site.
        color: theme.colorScheme.surface,
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 1,
                ),
              )
            : null,
      ),
      // Ink must paint above the row background painted by DecoratedBox.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(
            isDark ? AppPalette.darkHover : AppPalette.lightHover,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(
              children: [
                // `.article-list .figure` — 20x20 category icon.
                SizedBox(
                  width: 20,
                  height: 20,
                  child: figure != null
                      ? Image.asset(
                          figure,
                          width: 20,
                          height: 20,
                          filterQuality: FilterQuality.medium,
                        )
                      : Icon(
                          Icons.article_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                ),
                const SizedBox(width: 10),
                // `.article-list .title a` — single line, ellipsised.
                Expanded(
                  child: Text(
                    article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // `.badge.com` — reply count, always shown like the site.
                _Badge(
                  label: '${article.commentCount}',
                  icon: Icons.chat_bubble_outline,
                  background: badgeBg,
                  foreground: badgeFg,
                ),
                const SizedBox(width: 6),
                // `time.badge.red`
                if (timeText.isNotEmpty)
                  _Badge(
                    label: timeText,
                    background: badgeBg,
                    foreground: timeFg,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `08:39` out of `2026-09-27 08:39`, falling back to the raw date.
  static String _shortTime(ArticleListItem article) {
    final short =
        article.time.replaceFirst(RegExp(r'\d{4}-\d{2}-\d{2}\s*'), '').trim();
    if (short.isNotEmpty) return short;
    return article.date.trim();
  }
}

/// `.article-list .title .badge` — 10px pill, 3px/7px padding.
class _Badge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.label,
    this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
