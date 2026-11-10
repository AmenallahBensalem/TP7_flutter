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
/// - Source de vérité d'affichage : SQLite ([LocalQueueService]).
/// - Synchronisation vers Supabase via [SyncService] / [QueueRepository].
/// - Pagination de l'affichage local par pages de [pageSize] clients.
class QueueProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final LocalQueueService _localDb;
  final GeolocationService _geoService;
  late final QueueRepository _repository;
  late final SyncService _syncService;

  /// Taille d'une page d'affichage.
  static const int pageSize = 20;

  final List<Client> _allClients = [];
  int _visibleCount = pageSize;
  QueueState _state = QueueState.initial;
  String? _errorMessage;
  bool _isLoadingMore = false;

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

  // ── Getters ──────────────────────────────────────────────────────────

  /// Seulement la partie visible de la file (pagination de l'affichage).
  List<Client> get clients =>
      List.unmodifiable(_allClients.take(_visibleCount));

  QueueState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _visibleCount < _allClients.length;
  bool get isLoadingMore => _isLoadingMore;
  int get totalCount => _allClients.length;

  // ── Cycle de vie ─────────────────────────────────────────────────────

  Future<void> initialize() async {
    // Évite les abonnements en double (ex. bouton « Retry »).
    await _sub?.cancel();
    await _connSub?.cancel();

    _errorMessage = null;
    _state = QueueState.loading;
    notifyListeners();

    try {
      await _reloadFromLocal();
      _listen();
      _connSub = Connectivity().onConnectivityChanged.listen((results) {
        if (!results.contains(ConnectivityResult.none)) {
          _syncLocalToRemote();
        }
      });
      await _syncLocalToRemote();
    } catch (e) {
      debugPrint('Initialize failed: $e');
      _errorMessage = 'Failed to load queue';
      _state = QueueState.error;
      notifyListeners();
    }
  }

  /// Pull-to-refresh : resynchronise puis recharge.
  Future<void> refresh() async {
    _state = QueueState.refreshing;
    notifyListeners();
    await _syncLocalToRemote();
  }

  // ── Données locales ──────────────────────────────────────────────────

  Future<void> _reloadFromLocal() async {
    final rows = await _localDb.getClients();
    final loaded = rows.map(Client.fromLocalMap).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    _allClients
      ..clear()
      ..addAll(loaded);
    _state = _allClients.isEmpty ? QueueState.empty : QueueState.loaded;
    notifyListeners();
  }

  // ── Realtime ─────────────────────────────────────────────────────────

  /// Réconcilie la base locale avec Supabase (sans doublons : la clé
  /// primaire `id` + ConflictAlgorithm.replace font un upsert).
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

  /// Insertion Realtime sans doublon (par `id`).
  void handleRealtimeInsert(Client client) {
    if (_allClients.any((c) => c.id == client.id)) return;
    _allClients.add(client);
    _allClients.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (_state == QueueState.empty) _state = QueueState.loaded;
    notifyListeners();
  }

  // ── Synchronisation ──────────────────────────────────────────────────

  Future<void> _syncLocalToRemote() async {
    await _syncService.synchronize();
    await _reloadFromLocal();
  }

  // ── Pagination ───────────────────────────────────────────────────────

  /// Affiche la page suivante (la source locale contient déjà tout).
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 150));
    _visibleCount += pageSize;

    _isLoadingMore = false;
    notifyListeners();
  }

  // ── Actions ──────────────────────────────────────────────────────────

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
    // Retrait immédiat de la liste en mémoire (requis par Dismissible).
    _allClients.removeWhere((c) => c.id == id);
    if (_allClients.isEmpty) _state = QueueState.empty;
    notifyListeners();

    await _localDb.deleteClient(id);
    try {
      await _repository.deleteOnServer(id);
    } catch (e) {
      debugPrint('Remove failed (offline ?): $e');
    }
  }

  Future<void> nextClient() async {
    if (_allClients.isEmpty) return;
    await removeClient(_allClients.first.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}