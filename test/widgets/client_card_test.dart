import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/client.dart';
import 'package:waiting_room_app/widgets/client_card.dart';

void main() {
  testWidgets('shows location availability without exact coordinates',
      (tester) async {
    final client = Client(
      id: '1',
      name: 'Sam',
      lat: 51.5074,
      lng: -0.1278,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ClientCard(client: client))),
    );

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Location available'), findsOneWidget);
    expect(find.textContaining('51.5074'), findsNothing);
  });
}