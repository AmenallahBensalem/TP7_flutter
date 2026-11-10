import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  const WaitingRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waiting Room',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WaitingRoomPage(),
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
  const WaitingRoomPage({super.key});
  @override
  State<WaitingRoomPage> createState() => _WaitingRoomPageState();
}

class _WaitingRoomPageState extends State<WaitingRoomPage> {
  final _controller = TextEditingController();

  /// Lit le nom saisi, appelle [QueueProvider.addClient] et gère les erreurs.
  Future<void> _add() async {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a client name.')),
      );
      return;
    }

    _controller.clear();

    try {
      await context.read<QueueProvider>().addClient(name);
    } catch (e, stackTrace) {
      debugPrint('Add client error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add client: $e')),
      );
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
                return Dismissible(
                  key: ValueKey(c.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => provider.removeClient(c.id),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Waiting Room'), centerTitle: true),
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
                          decoration:
                              const InputDecoration(hintText: 'Enter name'),
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
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () =>
                        context.read<QueueProvider>().nextClient(),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next Client'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}