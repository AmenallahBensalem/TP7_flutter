import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/sync_status.dart';

class ClientCard extends StatelessWidget {
  final Client client;

  const ClientCard({super.key, required this.client});

  Widget? _syncIcon() => switch (client.syncStatus) {
        SyncStatus.synced => null,
        SyncStatus.failed =>
          const Icon(Icons.error_outline, color: Colors.red),
        _ => const Icon(Icons.cloud_upload_outlined, color: Colors.orange),
      };

  @override
  Widget build(BuildContext context) {
    final syncIcon = _syncIcon();
    final location =
        client.hasLocation ? 'Location available' : 'Location not captured';

    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(client.name),
        subtitle: Text(client.isSynced ? location : '$location • Pending sync'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?syncIcon,
            Icon(
              client.hasLocation ? Icons.location_on : Icons.location_off,
              color: client.hasLocation ? Colors.green : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}