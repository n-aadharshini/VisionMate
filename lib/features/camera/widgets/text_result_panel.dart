import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_ui.dart';

class TextResultPanel extends StatelessWidget {
  const TextResultPanel({
    super.key,
    required this.text,
    this.notice,
    this.timestamp,
    this.expanded = false,
    this.onToggleExpanded,
  });

  final String text;
  final String? notice;
  final DateTime? timestamp;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  String get _timestampLabel {
    if (timestamp == null) return '';
    final diff = DateTime.now().difference(timestamp!);
    if (diff.inSeconds < 30) return 'Detected just now';
    if (diff.inMinutes < 2) return 'Detected ${diff.inSeconds}s ago';
    return 'Detected ${diff.inMinutes} min ago';
  }

  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: notice != null
          ? Text(
              notice!,
              style: const TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w700,
              ),
            )
          : text.isEmpty
          ? Row(
              children: [
                const Icon(
                  Icons.document_scanner_rounded,
                  color: AppColors.cyan,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Point your camera towards text.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Text detected',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (_timestampLabel.isNotEmpty)
                      Text(
                        _timestampLabel,
                        style: TextStyle(
                          color: AppColors.muted.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: expanded ? 200 : 80),
                  child: SingleChildScrollView(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 17,
                        color: AppColors.text,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                if (text.length > 100)
                  TextButton(
                    onPressed: onToggleExpanded,
                    child: Text(expanded ? 'Show less' : 'Show more'),
                  ),
              ],
            ),
    ),
  );
}
