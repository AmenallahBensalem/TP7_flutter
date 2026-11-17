import 'package:flutter/material.dart';

import 'auth_repository.dart';
import 'profile.dart';

class PendingRequestsPage extends StatefulWidget {
  const PendingRequestsPage({
    super.key,
    required this.repository,
    required this.onBack,
  });

  final AuthRepository repository;
  final VoidCallback onBack;

  @override
  State<PendingRequestsPage> createState() => _PendingRequestsPageState();
}

class _PendingRequestsPageState extends State<PendingRequestsPage> {
  late Future<List<Profile>> _requests;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _requests = widget.repository.pendingProfiles();
  }

  void _reload() {
    setState(() => _requests = widget.repository.pendingProfiles());
  }

  Future<void> _review(Profile profile, {required bool approve}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.review(
        profile.id,
        approve: approve,
      );
      if (!mounted) return;
      _reload();
      _showMessage(
        updated
            ? (approve ? 'Demande acceptée.' : 'Demande refusée.')
            : 'Cette demande n’est plus disponible.',
      );
    } catch (error) {
      if (mounted) _showMessage(AuthRepository.errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('Demandes en attente'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _saving ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Profile>>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Chargement des demandes',
              ),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Impossible de charger les demandes. Utilisez Actualiser pour réessayer.',
                textAlign: TextAlign.center,
              ),
            );
          }
          final profiles = snapshot.requireData;
          if (profiles.isEmpty) {
            return const Center(child: Text('Aucune demande en attente.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final profile = profiles[index];
              return Card(
                key: ValueKey(profile.id),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName.isEmpty
                            ? profile.email
                            : profile.fullName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (profile.fullName.isNotEmpty) Text(profile.email),
                      if (profile.phone.isNotEmpty) Text(profile.phone),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _saving
                                ? null
                                : () => _review(profile, approve: true),
                            child: const Text('Accepter'),
                          ),
                          OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _review(profile, approve: false),
                            child: const Text('Refuser'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
