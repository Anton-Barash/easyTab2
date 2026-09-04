import 'package:flutter/material.dart';

class SyncButtons extends StatelessWidget {
  final bool showDownload;
  final bool showSync;
  final VoidCallback? onDownload;
  final VoidCallback? onSync;
  final bool inProgress;

  const SyncButtons({
    super.key,
    this.showDownload = false,
    this.showSync = false,
    this.onDownload,
    this.onSync,
    this.inProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    if (inProgress) {
      return const SizedBox(
        width: 56,
        height: 36,
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDownload)
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download',
            onPressed: onDownload,
          ),
        if (showSync)
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync',
            onPressed: onSync,
          ),
      ],
    );
  }
}
