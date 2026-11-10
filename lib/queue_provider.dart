import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'geolocation_service.dart';
import 'local_queue_service.dart';
import 'models/client.dart';
import 'models/sync_status.dart';
import 'repositories/queue_repository.dart';
import 'services/sync_service.dart';

/// Gestionnaire d'état de la file d'attente (offline-first).
class QueueProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final LocalQueueService _localDb;
  final GeolocationService _geoService;
  late final QueueRepository _repository;
  late final SyncService _syncService;

  List<Client> _clients = [];
  List<Client> get clients => _clients;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  

  QueueProvider({
    SupabaseClient? supabase,
    LocalQueueService? localDb,
    GeolocationService? geoService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _localDb = localDb ?? LocalQueueService(),
        _geoService = geoService ?? GeolocationService() {
    _repository = QueueRepository(_supabase, _localDb);
    _syncService = SyncService(_localDb, _repository);
  }
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
    _clients = rows.map(Client.fromLocalMap).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    notifyListeners();
  }

  /// Realtime : réconcilie la base locale avec Supabase (sans doublons,
  /// car la clé primaire `id` + ConflictAlgorithm.replace font un upsert).
  void _listen() {
    _sub = _supabase
        .from('clients')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .listen(
      (rows) async {
        final remoteIds = rows.map((r) => r['id'].toString()).toSet();

        for (final row in rows) {
          final remote = Client.fromSupabaseMap(row);
          await _localDb.insertClientLocally(remote.toLocalMap());
        }

        // Supprimer en local les clients synchronisés disparus à distance
        final local = await _localDb.getClients();
        for (final c in local.map(Client.fromLocalMap)) {
          if (c.isSynced && !remoteIds.contains(c.id)) {
            await _localDb.deleteClient(c.id);
          }
        }
        await _reloadFromLocal();
      },
      onError: (e) => debugPrint('Stream error: $e'),
    );
  }

  Future<void> _syncLocalToRemote() async {
    await _syncService.synchronize();
    await _reloadFromLocal();
  }

  Future<void> addClient(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    final position = await _geoService.getCurrentPosition();

    final client = Client(
      id: const Uuid().v4(),
      name: trimmedName,
      lat: position?.latitude,
      lng: position?.longitude,
      locationAccuracy: position?.accuracy,
      createdAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
    );

    await _localDb.insertClientLocally(client.toLocalMap());
    await _reloadFromLocal();
    unawaited(_syncLocalToRemote());
  }

  Future<void> removeClient(String id) async {
    await _localDb.deleteClient(id);
    await _reloadFromLocal();
    try {
      await _repository.deleteOnServer(id);
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