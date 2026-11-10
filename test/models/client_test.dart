import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/models/sync_status.dart';

void main() {
  group('Client Model Tests', () {
    test('client without location reports hasLocation as false', () {
      final client =
          Client(id: '1', name: 'Test', createdAt: DateTime.now());

      expect(client.hasLocation, isFalse);
      expect(client.locationText, equals('Location not captured'));
    });

    test('toLocalMap preserves accuracy and syncStatus', () {
      final client = Client(
        id: '1',
        name: 'Test',
        lat: 36.8065,
        lng: 10.1815,
        locationAccuracy: 5.5,
        createdAt: DateTime.utc(2026, 1, 1),
        syncStatus: SyncStatus.pending,
      );

      final map = client.toLocalMap();

      expect(map['location_accuracy_m'], equals(5.5));
      expect(map['sync_status'], equals('pending'));
    });

    test('toSupabaseMap excludes local sync_status', () {
      final client = Client(
        id: '1',
        name: 'Test',
        createdAt: DateTime.now(),
        syncStatus: SyncStatus.pending,
      );

      expect(client.toSupabaseMap().containsKey('sync_status'), isFalse);
    });

    test('fromLocalMap round-trip keeps data', () {
      final original = Client(
        id: 'abc',
        name: 'Alice',
        lat: 1.5,
        lng: 2.5,
        createdAt: DateTime.utc(2026, 10, 20),
        syncStatus: SyncStatus.failed,
      );

      final copy = Client.fromLocalMap(original.toLocalMap());

      expect(copy.id, 'abc');
      expect(copy.syncStatus, SyncStatus.failed);
      expect(copy.createdAt, DateTime.utc(2026, 10, 20));
    });

    test('fromLocalMap falls back to pending for unknown status', () {
      final c = Client.fromLocalMap({
        'id': '1',
        'name': 'X',
        'created_at': '2026-01-01T00:00:00.000Z',
        'sync_status': 'weird',
      });
      expect(c.syncStatus, SyncStatus.pending);
    });
  });
}