import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/local_queue_service.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/repositories/queue_repository.dart';
import 'package:waiting_room_app/services/sync_service.dart';

class MockQueueRepository extends Mock implements QueueRepository {}

class FakeClient extends Fake implements Client {}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalQueueService storage;
  late MockQueueRepository repo;
  late SyncService sync;

  setUpAll(() => registerFallbackValue(FakeClient()));

  setUp(() {
    storage = LocalQueueService(inMemory: true);
    repo = MockQueueRepository();
    sync = SyncService(storage, repo);
  });

  tearDown(() => storage.close());

  Future<void> insertPending(String id) => storage.insertClientLocally({
        'id': id,
        'name': 'User $id',
        'created_at': '2024-01-01T00:00:00Z',
        'sync_status': 'pending',
      });

  test('successful sync marks client as synced', () async {
    await insertPending('c1');
    when(() => repo.registerOnServer(any())).thenAnswer((_) async {});

    final count = await sync.synchronize();

    expect(count, 1);
    expect(await storage.getUnsyncedClients(), isEmpty);
  });

  test('failed sync marks client as failed and keeps it for retry', () async {
    await insertPending('c2');
    when(() => repo.registerOnServer(any())).thenThrow(Exception('offline'));

    final count = await sync.synchronize();
    final unsynced = await storage.getUnsyncedClients();

    expect(count, 0);
    expect(unsynced.length, 1);
    expect(unsynced.first['sync_status'], 'failed');
  });

  test('one failure does not stop the other clients', () async {
    await insertPending('c3');
    await insertPending('c4');
    var calls = 0;
    when(() => repo.registerOnServer(any())).thenAnswer((_) async {
      if (calls++ == 0) throw Exception('boom');
    });

    final count = await sync.synchronize();

    expect(count, 1);
  });
}