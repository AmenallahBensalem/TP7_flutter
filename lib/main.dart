import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_repository.dart';
import 'providers/connectivity_provider.dart';
import 'services/connectivity_service.dart';
import 'waiting_room_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Supabase Flutter restaure la session locale. AuthGate vérifie le profil.
  final client = Supabase.instance.client;
  runApp(
    ChangeNotifierProvider(
      create: (_) =>
          ConnectivityProvider(ConnectivityService(client))..initialize(),
      child: WaitingRoomApp(repository: AuthRepository(client)),
    ),
  );
}
