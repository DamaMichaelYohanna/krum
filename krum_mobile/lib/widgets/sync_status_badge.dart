import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../providers/store_provider.dart';
import '../services/sync_service.dart';

class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final status = provider.syncStatus;
    final pending = provider.pendingSyncCount;

    Color color;
    String label;
    IconData icon;

    switch (status) {
      case SyncStatus.syncing:
        color = Colors.blue;
        label = 'Syncing...';
        icon = Icons.sync;
        break;
      case SyncStatus.pending:
        color = Colors.orange;
        label = '$pending pending';
        icon = Icons.cloud_upload_outlined;
        break;
      case SyncStatus.failed:
        color = Colors.red;
        label = 'Sync failed';
        icon = Icons.sync_problem_outlined;
        break;
      case SyncStatus.synced:
        color = AppColors.primary;
        label = 'Synced';
        icon = Icons.check_circle_outline;
        break;
    }

    return InkWell(
      onTap: () async {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Synchronizing with server...'),
            duration: Duration(seconds: 1),
          ),
        );
        await provider.syncNow();
        if (context.mounted && provider.syncStatus == SyncStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${provider.syncError}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
