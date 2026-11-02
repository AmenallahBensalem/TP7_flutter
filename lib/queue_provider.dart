import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'geolocation_service.dart';
import 'local_queue_service.dart';
import 'models/client.dart';

class QueueProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final LocalQueueService _localDb;
  final GeolocationService _geoService;

  List<Client> _clients = [];
  List<Client> get clients => _clients;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _syncing = false;

  QueueProvider({
    SupabaseClient? supabase,
    LocalQueueService? localDb,
    GeolocationService? geoService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _localDb = localDb ?? LocalQueueService(),
        _geoService = geoService ?? GeolocationService();

  /// À appeler une fois au démarrage (voir main.dart)
  Future<void> initialize() async {
    await _reloadFromLocal();
    _listen();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        _syncLocalToRemote();
      }
    });
    await _syncLocalToRemote();
  }

  Future<void> _reloadFromLocal() async {
    final rows = await _localDb.getClients();
    _clients = rows.map(Client.fromMap).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    notifyListeners();
  }

  // Temps réel : Supabase -> base locale -> UI
  void _listen() {
    _sub = _supabase
        .from('clients')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .listen(
      (rows) async {
        final remoteIds = rows.map((r) => r['id'].toString()).toSet();

        for (final row in rows) {
          await _localDb.insertClientLocally({
            'id': row['id'].toString(),
            'name': row['name'],
            'lat': row['lat'],
            'lng': row['lng'],
            'created_at': row['created_at'].toString(),
            'is_synced': 1,
          });
        }

        // Supprimer en local les clients synchronisés qui n'existent plus à distance
        final local = await _localDb.getClients();
        for (final c in local) {
          if (c['is_synced'] == 1 && !remoteIds.contains(c['id'])) {
            await _localDb.deleteClient(c['id'] as String);
          }
        }
        await _reloadFromLocal();
      },
      onError: (e) => debugPrint('Stream error: $e'),
    );
  }

  // Local -> Supabase
  Future<void> _syncLocalToRemote() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final unsynced = await _localDb.getUnsyncedClients();
      for (final client in unsynced) {
        try {
          final remote = Map<String, dynamic>.from(client)
            ..remove('is_synced');
          await _supabase.from('clients').upsert(remote);
          await _localDb.markClientAsSynced(client['id'] as String);
        } catch (e) {
          debugPrint('Sync failed for ${client['id']}: $e');
        }
      }
      await _reloadFromLocal();
    } finally {
      _syncing = false;
    }
  }

  Future<void> addClient(String name) async {
    if (name.trim().isEmpty) return;

    final position = await _geoService.getCurrentPosition();

    await _localDb.insertClientLocally({
      'id': const Uuid().v4(),
      'name': name.trim(),
      'lat': position?.latitude,
      'lng': position?.longitude,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 0,
    });

    await _reloadFromLocal(); // l'UI se met à jour tout de suite
    unawaited(_syncLocalToRemote());
  }

  Future<void> removeClient(String id) async {
    await _localDb.deleteClient(id);
    await _reloadFromLocal();
    try {
      await _supabase.from('clients').delete().eq('id', id);
    } catch (e) {
      debugPrint('Remove failed (offline ?): $e');
    }
  }

  Future<void> nextClient() async {
    if (_clients.isEmpty) return;
    await removeClient(_clients.first.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}