import 'package:flutter/material.dart';
import '../models/article.dart';

/// A card displaying a single article in a list.
class ArticleCard extends StatelessWidget {
  final ArticleListItem article;
  final VoidCallback onTap;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeText = article.time.isNotEmpty
        ? article.time.replaceFirst(
            RegExp(r'\d{4}-\d{2}-\d{2}\s*'), '')
        : article.date;

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                article.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Category + time + author
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (article.category.isNotEmpty)
                    _Chip(
                      label: article.category,
                      color: theme.colorScheme.primaryContainer,
                    ),
                  if (timeText.isNotEmpty)
                    _Chip(
                      label: timeText,
                      icon: Icons.access_time,
                      color: theme.colorScheme
                          .surfaceContainerHighest,
                    ),
                  if (article.author.isNotEmpty)
                    _Chip(
                      label: article.author,
                      icon: Icons.person_outline,
                      color: theme.colorScheme
                          .surfaceContainerHighest,
                    ),
                  if (article.commentCount > 0)
                    _Chip(
                      label: '${article.commentCount}',
                      icon: Icons.chat_bubble_outline,
                      color: theme.colorScheme
                          .secondaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Summary
              if (article.summary.isNotEmpty)
                Text(
                  article.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 4),
              // Read full article
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '阅读全文',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  const _Chip({
    required this.label,
    this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: 12),
            ),
          Text(
            label,
            style: theme.textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}