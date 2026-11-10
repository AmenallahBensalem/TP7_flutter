import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/widgets/queue_empty_widget.dart';

void main() {
  testWidgets('shows empty message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QueueEmptyWidget())),
    );

    expect(find.text('The waiting queue is empty'), findsOneWidget);
  });
}