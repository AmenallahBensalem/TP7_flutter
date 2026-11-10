
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/connectivity_provider.dart';
import 'queue_provider.dart';
import 'services/connectivity_service.dart';
import 'waiting_room_app.dart';

/// Point d'entrée de l'application Waiting Room App.
///
/// Séquence d'initialisation :
/// 1. Charger les variables d'environnement depuis .env
/// 2. Initialiser Supabase
/// 3. Vérifier ou rafraîchir la session anonyme
/// 4. Initialiser les Providers
/// 5. Lancer l'application Flutter

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Charger les variables d'environnement
  await dotenv.load(fileName: '.env');

  // 2. Initialiser Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 3. Gestion de l'authentification Supabase
  final auth = Supabase.instance.client.auth;

  try {
    if (auth.currentSession == null) {
      // Créer une nouvelle session anonyme
      await auth.signInAnonymously();

      debugPrint('AUTH: Nouvelle session créée');
    } else if (auth.currentSession!.isExpired) {
      // Rafraîchir le token JWT expiré
      await auth.refreshSession();

      debugPrint('AUTH: Token rafraîchi');
    } else {
      // La session actuelle est encore valide
      debugPrint('AUTH: Session toujours valide');
    }

    // Afficher les informations de diagnostic
    debugPrint(
      'AUTH USER ID: ${auth.currentUser?.id}',
    );

    debugPrint(
      'AUTH EXPIRED: ${auth.currentSession?.isExpired}',
    );
  } catch (e) {
    // L'application peut démarrer hors ligne
    debugPrint('AUTH ERROR: $e');
  }

  // 4. Initialiser les Providers et lancer l'application
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ConnectivityProvider(
            ConnectivityService(
              Supabase.instance.client,
            ),
          )..initialize(),
        ),

        ChangeNotifierProvider(
          create: (_) => QueueProvider()
            ..initialize(),
        ),
      ],

      // 5. Interface principale
      child: const WaitingRoomApp(),
    ),
  );
}
