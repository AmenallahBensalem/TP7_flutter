import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local_queue_service.dart';
import '../queue_provider.dart';
import '../waiting_room_app.dart';
import 'auth_form.dart';
import 'auth_repository.dart';
import 'profile.dart';

/// N'instancie la file qu'après vérification du profil côté Supabase.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _subscription;
  Profile? _profile;
  String? _message;
  String? _error;
  bool _checking = false;
  bool _signingOut = false;
  int _request = 0;

  AuthRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _repository.auth.onAuthStateChange.listen(
      (_) => unawaited(_checkSession()),
      onError: (Object error) => debugPrint('Auth session: $error'),
    );
    unawaited(_checkSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkSession());
  }

  Future<void> _checkSession() async {
    if (_signingOut) return;
    final request = ++_request;
    final user = _repository.auth.currentUser;
    setState(() {
      if (_profile?.id != user?.id) _profile = null;
      _checking = user != null;
      _error = null;
      if (user != null) _message = null;
    });
    if (user == null) return;

    try {
      final profile = user.isAnonymous
          ? null
          : await _repository.getProfile(user.id);
      if (!mounted || request != _request) return;
      switch (profile?.status) {
        case AccountStatus.approved:
          setState(() {
            _profile = profile;
            _checking = false;
          });
        case AccountStatus.pending:
          await _signOut(message: 'Votre compte est en attente de validation');
        case AccountStatus.rejected:
          await _signOut(message: 'Votre demande a été refusée');
        case null:
          await _signOut(
            message: user.isAnonymous
                ? null
                : 'Profil introuvable. Contactez l’administrateur.',
          );
      }
    } catch (error) {
      if (!mounted || request != _request) return;
      debugPrint('Profile check: $error');
      setState(() {
        _profile = null;
        _checking = false;
        _error = 'Impossible de vérifier votre compte. Réessayez en ligne.';
      });
    }
  }

  Future<void> _signOut({String? message}) async {
    if (_signingOut) return;
    ++_request;
    setState(() {
      _profile = null;
      _signingOut = true;
      _message = message;
      _error = null;
    });
    try {
      await _repository.signOut().timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('Sign out: $error');
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
          _checking = false;
          if (_repository.auth.currentSession != null) {
            _error = 'Impossible de terminer la déconnexion. Réessayez.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile != null) {
      return ChangeNotifierProvider(
        key: ValueKey(profile.id),
        create: (_) => QueueProvider(
          supabase: _repository.client,
          localDb: LocalQueueService(accountId: profile.id),
        )..initialize(),
        child: WaitingRoomPage(
          profile: profile,
          repository: _repository,
          onSignOut: _signOut,
        ),
      );
    }
    if (_checking || _signingOut) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Vérification de votre compte',
          ),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error),
                if (_message != null) Text(_message!),
                FilledButton(
                  onPressed: _checkSession,
                  child: const Text('Réessayer'),
                ),
                TextButton(
                  onPressed: () => _signOut(message: _message),
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return AuthForm(repository: _repository, message: _message);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
