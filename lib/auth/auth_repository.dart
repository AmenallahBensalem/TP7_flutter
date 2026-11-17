import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile.dart';

class AuthRepository {
  AuthRepository(this.client);

  final SupabaseClient client;
  GoTrueClient get auth => client.auth;

  Future<void> signIn(String email, String password) async {
    await auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    await auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone},
    );
  }

  Future<void> signOut() => auth.signOut(scope: SignOutScope.local);

  Future<Profile?> getProfile(String id) async {
    final row = await client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Profile.fromRow(row);
  }

  Future<List<Profile>> pendingProfiles() async {
    final rows = await client
        .from('profiles')
        .select()
        .eq('status', AccountStatus.pending.name)
        .order('created_at')
        .order('id');
    return rows.map(Profile.fromRow).toList();
  }

  Future<bool> review(String id, {required bool approve}) async {
    final status = approve ? AccountStatus.approved : AccountStatus.rejected;
    final row = await client
        .from('profiles')
        .update({'status': status.name})
        .eq('id', id)
        .eq('status', AccountStatus.pending.name)
        .select('id')
        .maybeSingle();
    return row != null;
  }

  static String errorMessage(Object error) {
    if (error is AuthException) {
      switch (error.code) {
        case 'invalid_credentials':
          return 'Email ou mot de passe incorrect.';
        case 'email_not_confirmed':
          return 'Confirmez votre adresse email avant de vous connecter.';
        case 'user_already_exists':
        case 'email_exists':
          return 'Un compte utilise déjà cette adresse email.';
        case 'weak_password':
          return 'Choisissez un mot de passe plus fort.';
        case 'over_request_rate_limit':
        case 'over_email_send_rate_limit':
          return 'Trop de tentatives. Réessayez dans quelques instants.';
      }
    }
    return 'L’opération a échoué. Vérifiez votre connexion et réessayez.';
  }
}
