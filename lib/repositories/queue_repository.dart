import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/client.dart';
import '../local_queue_service.dart';

/// Coordonne l'accès aux données distantes (Supabase) et locales (SQLite).
class QueueRepository {
  final SupabaseClient _supabase;
  final LocalQueueService _local;
  final String? _accountId;

  QueueRepository(this._supabase, this._local)
    : _accountId = _supabase.auth.currentUser?.id;

  LocalQueueService get local => _local;

  /// Enregistre un client côté serveur via la fonction RPC (idempotent).
  Future<void> registerOnServer(Client client) async {
    _requireCurrentAccount();
    await _supabase.rpc(
      'register_queue_client',
      params: {
        'p_id': client.id,
        'p_name': client.name,
        'p_lat': client.lat,
        'p_lng': client.lng,
        'p_accuracy': client.locationAccuracy,
        'p_created_at': client.createdAt.toUtc().toIso8601String(),
      },
    );
  }

  /// Récupère une page de clients, triés par date de création croissante.
  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    final rows = await _supabase
        .from('clients')
        .select()
        .order('created_at', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + limit - 1);

    return rows.map<Client>(Client.fromSupabaseMap).toList();
  }

  Future<void> deleteOnServer(String id) async {
    _requireCurrentAccount();
    final row = await _supabase
        .from('clients')
        .delete()
        .eq('id', id)
        .select('id')
        .maybeSingle();
    if (row == null) {
      throw StateError('Client indisponible pour la suppression.');
    }
  }

  Future<String> nextOnServer(String expectedId) async {
    _requireCurrentAccount();
    return await _supabase.rpc<String>(
      'next_client',
      params: {'p_expected_id': expectedId},
    );
  }

  void _requireCurrentAccount() {
    if (_accountId == null || _supabase.auth.currentUser?.id != _accountId) {
      throw StateError('La session a changé.');
    }
  }
}
