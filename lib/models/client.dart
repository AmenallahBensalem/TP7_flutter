import 'sync_status.dart';

/// Client de la file d'attente.
///
/// [toSupabaseMap] contient uniquement les données métier.
/// [toLocalMap] ajoute le statut de synchronisation (local uniquement).
class Client {
  final String id;
  final String name;
  final double? lat;
  final double? lng;
  final double? locationAccuracy;
  final DateTime createdAt;
  final SyncStatus syncStatus;

  const Client({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
    this.locationAccuracy,
    required this.createdAt,
    this.syncStatus = SyncStatus.synced,
  });

  bool get hasLocation => lat != null && lng != null;
  bool get isSynced => syncStatus == SyncStatus.synced;

  String get locationText {
    if (!hasLocation) return 'Location not captured';
    return '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}';
  }

  Map<String, dynamic> toSupabaseMap() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'location_accuracy_m': locationAccuracy,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toLocalMap() => {
        ...toSupabaseMap(),
        'sync_status': syncStatus.name,
      };

  factory Client.fromSupabaseMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'].toString(),
      name: map['name'] as String,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'].toString()),
      syncStatus: SyncStatus.synced,
    );
  }

  factory Client.fromLocalMap(Map<String, dynamic> map) {
    return Client(
      id: map['id'] as String,
      name: map['name'] as String,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'].toString()),
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == map['sync_status'],
        orElse: () => SyncStatus.pending,
      ),
    );
  }

  @override
  String toString() => 'Client(id: $id, name: $name, status: ${syncStatus.name})';
}