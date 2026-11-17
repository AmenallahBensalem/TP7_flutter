
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'geolocation_service.dart';
import 'local_queue_service.dart';
import 'models/client.dart';
import 'models/queue_state.dart';
import 'models/sync_status.dart';
import 'repositories/queue_repository.dart';
import 'services/sync_service.dart';

/// Gestionnaire d'état de la file d'attente (offline-first).
///
/// - Source de vérité : SQLite (LocalQueueService).
/// - Synchronisation Supabase via SyncService.
/// - Realtime avec gestion du rafraîchissement du token.
/// - Pagination locale par pages de 20 clients.
class QueueProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final LocalQueueService _localDb;
  final GeolocationService _geoService;

  late final QueueRepository _repository;
  late final SyncService _syncService;

  static const int pageSize = 20;

  final List<Client> _allClients = [];

  int _visibleCount = pageSize;

  QueueState _state = QueueState.initial;
  String? _errorMessage;
  bool _isLoadingMore = false;
  bool _disposed = false;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Abonnement aux changements d'authentification Supabase.
  StreamSubscription<AuthState>? _authSub;

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

  // ── Getters ──────────────────────────────────────────

  List<Client> get clients =>
      List.unmodifiable(_allClients.take(_visibleCount));

  QueueState get state => _state;
  String? get errorMessage => _errorMessage;

  bool get hasMore => _visibleCount < _allClients.length;
  bool get isLoadingMore => _isLoadingMore;
  int get totalCount => _allClients.length;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ── Initialisation ───────────────────────────────────

  Future<void> initialize() async {
    // Éviter les abonnements en double.
    await _sub?.cancel();
    await _connSub?.cancel();
    await _authSub?.cancel();

    if (_disposed) return;

    _errorMessage = null;
    _state = QueueState.loading;
    _notify();

    try {
      // 1. Charger les données SQLite.
      await _reloadFromLocal();

      if (_disposed) return;

      // 2. Écouter les changements d'authentification.
      _authSub = _supabase.auth.onAuthStateChange.listen(
        (data) {
          if (data.event == AuthChangeEvent.tokenRefreshed ||
              data.event == AuthChangeEvent.signedIn) {
            debugPrint(
              'Supabase authentication updated: ${data.event}',
            );

            // Redémarrer Realtime avec la session actualisée.
            unawaited(_restartRealtime());
          }
        },
        onError: (Object error) {
          debugPrint('Authentication stream error: $error');
        },
      );

      // 3. Démarrer Realtime si une session existe.
      if (_supabase.auth.currentSession != null) {
        _listen();
      } else {
        debugPrint(
          'Realtime waiting for Supabase authentication.',
        );
      }

      // 4. Écouter le retour de la connexion Internet.
      _connSub = Connectivity().onConnectivityChanged.listen(
        (results) {
          if (!results.contains(ConnectivityResult.none)) {
            debugPrint('Network available: syncing queue.');
            unawaited(_syncLocalToRemote());
          }
        },
        onError: (Object error) {
          debugPrint('Connectivity error: $error');
        },
      );

      // 5. Synchroniser les données.
      await _syncLocalToRemote();
    } catch (e, stackTrace) {
      debugPrint('Queue initialization failed (${e.runtimeType}): $e');
      debugPrintStack(stackTrace: stackTrace);

      if (_disposed) return;

      _errorMessage = 'Failed to load queue';
      _state = QueueState.error;
      _notify();
    }
  }

  // ── Rafraîchissement manuel ─────────────────────────

  Future<void> refresh() async {
    if (_disposed) return;

    _state = QueueState.refreshing;
    _notify();

    try {
      await _syncLocalToRemote();
      await _restartRealtime();
    } catch (e) {
      debugPrint('Refresh failed: $e');

      if (_disposed) return;

      _errorMessage = 'Failed to refresh queue';
      _state = QueueState.error;
      _notify();
    }
  }

  // ── SQLite ───────────────────────────────────────────

  Future<void> _reloadFromLocal() async {
    final rows = await _localDb.getClients();

    if (_disposed) return;

    final loaded = rows.map(Client.fromLocalMap).toList()
      ..sort(_compareClients);

    _allClients
      ..clear()
      ..addAll(loaded);

    _state = _allClients.isEmpty
        ? QueueState.empty
        : QueueState.loaded;

    _notify();
  }

  static int _compareClients(Client a, Client b) {
    final byDate = a.createdAt.compareTo(b.createdAt);
    return byDate == 0 ? a.id.compareTo(b.id) : byDate;
  }

  // ── Supabase Realtime ────────────────────────────────

  void _listen() {
    if (_disposed) return;

    if (_supabase.auth.currentSession == null) {
      debugPrint('Realtime skipped: no active session.');
      return;
    }

    _sub = _supabase
        .from('clients')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .listen(
      (rows) async {
        try {
          if (_disposed) return;

          final remoteIds =
              rows.map((r) => r['id'].toString()).toSet();

          // Enregistrer les données distantes dans SQLite.
          for (final row in rows) {
            final remote = Client.fromSupabaseMap(row);

            await _localDb.insertClientLocally(
              remote.toLocalMap(),
            );
          }

          // Supprimer les clients synchronisés
          // qui ont disparu du serveur.
          final local = await _localDb.getClients();

          for (final c in local.map(Client.fromLocalMap)) {
            if (c.isSynced && !remoteIds.contains(c.id)) {
              await _localDb.deleteClient(c.id);
            }
          }

          await _reloadFromLocal();
        } catch (e) {
          debugPrint('Realtime processing error: $e');
        }
      },
      onError: (Object error) {
        debugPrint('Stream error: $error');

        // La reconnexion sera déclenchée lors
        // du prochain changement d'authentification.
      },
    );
  }

  // ── Redémarrage Realtime ─────────────────────────────

  Future<void> _restartRealtime() async {
    if (_disposed) return;

    debugPrint('Restarting Supabase Realtime...');

    // Fermer l'ancien abonnement.
    await _sub?.cancel();
    _sub = null;

    if (_disposed) return;

    // Relancer uniquement avec une session valide.
    if (_supabase.auth.currentSession != null) {
      _listen();
      debugPrint('Realtime listener restarted.');
    }
  }

  // ── Insertion Realtime ───────────────────────────────

  void handleRealtimeInsert(Client client) {
    if (_disposed) return;

    if (_allClients.any((c) => c.id == client.id)) {
      return;
    }

    _allClients.add(client);

    _allClients.sort(_compareClients);

    if (_state == QueueState.empty) {
      _state = QueueState.loaded;
    }

    _notify();
  }

  // ── Synchronisation ──────────────────────────────────

  Future<void> _syncLocalToRemote() async {
    if (_disposed) return;

    try {
      await _syncService.synchronize();

      if (_disposed) return;

      await _reloadFromLocal();
    } catch (e) {
      debugPrint('Synchronization failed: $e');

      // Ne pas supprimer les données locales.
      // Elles seront synchronisées ultérieurement.
      if (!_disposed) {
        await _reloadFromLocal();
      }
    }
  }

  // ── Pagination ───────────────────────────────────────

  Future<void> loadMore() async {
    if (_disposed || _isLoadingMore || !hasMore) return;

    _isLoadingMore = true;
    _notify();

    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    if (_disposed) return;

    _visibleCount += pageSize;
    _isLoadingMore = false;

    _notify();
  }

  // ── Ajouter un client ────────────────────────────────

  Future<void> addClient(String name) async {
  debugPrint('ADD STEP 1: Button clicked');

  final trimmedName = name.trim();

  if (trimmedName.isEmpty) {
    debugPrint('ADD ERROR: Empty name');
    return;
  }

  try {
    debugPrint('ADD STEP 2: Getting GPS');

    final position = await _geoService.getCurrentPosition();

    debugPrint('ADD STEP 3: GPS completed');

    final client = Client(
      id: const Uuid().v4(),
      name: trimmedName,
      lat: position?.latitude,
      lng: position?.longitude,
      locationAccuracy: position?.accuracy,
      createdAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
    );

    debugPrint('ADD STEP 4: Saving to SQLite');

    await _localDb.insertClientLocally(
      client.toLocalMap(),
    );

    debugPrint('ADD STEP 5: SQLite insertion successful');

    await _reloadFromLocal();

    debugPrint('ADD STEP 6: Local list refreshed');

    await _syncLocalToRemote();

    debugPrint('ADD STEP 7: Sync attempt completed');
  } catch (e, stackTrace) {
    debugPrint('ADD ERROR: $e');
    debugPrintStack(stackTrace: stackTrace);
    rethrow;
  }
}

  // ── Supprimer un client ──────────────────────────────

  Future<void> removeClient(String id) async {
    if (_disposed) return;
    await _repository.deleteOnServer(id);
    await _localDb.deleteClient(id);
    if (!_disposed) await _reloadFromLocal();
  }

  // ── Client suivant ───────────────────────────────────

  Future<void> nextClient() async {
    if (_allClients.isEmpty || _disposed) return;

    final id = await _repository.nextOnServer(_allClients.first.id);
    await _localDb.deleteClient(id);
    if (!_disposed) await _reloadFromLocal();
  }

  // ── Libération des ressources ────────────────────────

  @override
  void dispose() {
    _disposed = true;

    _sub?.cancel();
    _connSub?.cancel();
    _authSub?.cancel();

    super.dispose();
  }
}
