import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_repository.dart';
import 'auth/pending_requests_page.dart';
import 'auth/profile.dart';
import 'models/queue_state.dart';
import 'providers/connectivity_provider.dart';
import 'queue_provider.dart';
import 'widgets/client_card.dart';
import 'widgets/loading_widget.dart';
import 'widgets/offline_banner.dart';
import 'widgets/queue_empty_widget.dart';

/// Widget racine de l'application Waiting Room.
///
/// Configure le thème Material et définit [WaitingRoomPage] comme écran
/// principal.
class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key, required this.repository});

  final AuthRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waiting Room',
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      home: AuthGate(repository: repository),
    );
  }
}

/// Page principale affichant la file d'attente.
///
/// Permet à l'utilisateur de :
/// - **Ajouter** un client (champ texte + bouton « Add »)
/// - **Voir** la liste paginée des clients (états : chargement, vide,
///   erreur, liste)
/// - **Supprimer** un client (glisser vers la gauche)
/// - **Rafraîchir** (pull-to-refresh)
/// - **Passer au suivant** (bouton « Next Client »)
///
/// Affiche une [OfflineBanner] en haut selon l'état de la connexion.
class WaitingRoomPage extends StatefulWidget {
  const WaitingRoomPage({
    super.key,
    required this.profile,
    required this.repository,
    required this.onSignOut,
  });

  final Profile profile;
  final AuthRepository repository;
  final Future<void> Function() onSignOut;

  @override
  State<WaitingRoomPage> createState() => _WaitingRoomPageState();
}

class _WaitingRoomPageState extends State<WaitingRoomPage> {
  final _controller = TextEditingController();
  bool _requestsOpen = false;
  bool _nextBusy = false;

  @override
  void didUpdateWidget(covariant WaitingRoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.profile.isAdmin) _requestsOpen = false;
  }

  Future<void> _nextClient() async {
    if (_nextBusy) return;
    setState(() => _nextBusy = true);
    try {
      await context.read<QueueProvider>().nextClient();
    } catch (error) {
      if (!mounted) return;
      final message = error is PostgrestException && error.code == 'P0001'
          ? 'La file a changé. Actualisez avant de réessayer.'
          : 'Impossible de passer au client suivant. Vérifiez votre connexion et vos droits.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _nextBusy = false);
    }
  }

  Future<bool> _deleteClient(QueueProvider provider, String id) async {
    try {
      await provider.removeClient(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de supprimer ce client.')),
        );
      }
    }
    // Le provider retire la carte après confirmation de Supabase.
    return false;
  }

  /// Lit le nom saisi, appelle [QueueProvider.addClient] et gère les erreurs.
  Future<void> _add() async {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a client name.')));
      return;
    }

    _controller.clear();

    try {
      await context.read<QueueProvider>().addClient(name);
    } catch (e, stackTrace) {
      debugPrint('Add client error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to add client: $e')));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Corps de la liste selon l'état de [QueueProvider].
  Widget _buildQueue(QueueProvider provider) {
    switch (provider.state) {
      case QueueState.initial:
      case QueueState.loading:
        return const LoadingWidget(message: 'Loading queue...');

      case QueueState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(provider.errorMessage ?? 'Something went wrong'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: provider.initialize,
                child: const Text('Retry'),
              ),
            ],
          ),
        );

      case QueueState.empty:
        return const QueueEmptyWidget();

      case QueueState.loaded:
      case QueueState.refreshing:
      case QueueState.loadingMore:
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
              provider.loadMore();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: provider.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: provider.clients.length + (provider.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= provider.clients.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final c = provider.clients[i];
                if (!widget.profile.isAdmin) return ClientCard(client: c);
                return Dismissible(
                  key: ValueKey(c.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) => _deleteClient(provider, c.id),
                  child: ClientCard(client: c),
                );
              },
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.profile.isAdmin;
    if (isAdmin && _requestsOpen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _requestsOpen = false);
        },
        child: PendingRequestsPage(
          repository: widget.repository,
          onBack: () => setState(() => _requestsOpen = false),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Waiting Room'),
            Text(
              isAdmin ? 'Connecté : Admin' : 'Connecté : Utilisateur',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Demandes en attente',
              onPressed: () => setState(() => _requestsOpen = true),
              icon: const Icon(Icons.how_to_reg),
            ),
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          // Bannière de connectivité (pleine largeur, masquée si online)
          Consumer<ConnectivityProvider>(
            builder: (_, conn, _) => OfflineBanner(status: conn.status),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Enter name',
                          ),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _add, child: const Text('Add')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Consumer<QueueProvider>(
                      builder: (context, provider, _) => _buildQueue(provider),
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: 20),
                    Consumer<QueueProvider>(
                      builder: (context, queue, _) => ElevatedButton.icon(
                        onPressed: _nextBusy || queue.clients.isEmpty
                            ? null
                            : _nextClient,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(_nextBusy ? 'En cours…' : 'Next Client'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
