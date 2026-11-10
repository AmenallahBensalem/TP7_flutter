import '../local_queue_service.dart';
import '../models/client.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';

/// Envoie les clients locaux non synchronisés vers Supabase.
class SyncService {
  final LocalQueueService _storage;
  final QueueRepository _repository;
  bool _isSyncing = false;

  SyncService(this._storage, this._repository);

  bool get isSyncing => _isSyncing;

  /// Retourne le nombre de clients synchronisés avec succès.
  Future<int> synchronize() async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    var successCount = 0;

    try {
      final pending = await _storage.getUnsyncedClients();

      for (final record in pending) {
        final id = record['id'] as String;
        try {
          await _storage.updateSyncStatus(id, SyncStatus.syncing);
          final client = Client.fromLocalMap(record);
          await _repository.registerOnServer(client);
          await _storage.updateSyncStatus(id, SyncStatus.synced);
          successCount++;
        } catch (_) {
          await _storage.updateSyncStatus(id, SyncStatus.failed);
        }
      }
    } finally {
      _isSyncing = false;
    }
    return successCount;
  }
}