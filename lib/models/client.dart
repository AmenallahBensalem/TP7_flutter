
class Client {
  final String id;
  final String name;
  final double? lat;
  final double? lng;
  final DateTime createdAt;
  final bool isSynced;

  Client({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
    required this.createdAt,
    this.isSynced = true,
  });

  factory Client.fromMap(Map<String, dynamic> m) {
    return Client(
      id: m['id'].toString(),
      name: m['name'] as String,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      createdAt: DateTime.parse(m['created_at'].toString()),
      isSynced: (m['is_synced'] as num?)?.toInt() == 1,
    );
  }
  
Map<String, dynamic> toMap() {
  return {
    'id': id,
    'name': name,
    'lat': lat,
    'lng': lng,
    'created_at': createdAt.toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
  };
}

  @override
  String toString() => 'Client(id: $id, name: $name, created_at: $createdAt)';

}
