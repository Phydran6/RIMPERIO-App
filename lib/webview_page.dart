// ---------------------------------------------------------------------------
// Datei:        lib/webview_page.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.05.12.00.00
//
// Beschreibung: Die eigentliche App: eine WebView auf die RIMPERIO-Oberfläche.
//               Zurück-Taste blättert in der Seite; über das Menü lässt sich
//               neu laden oder der Server wechseln.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'storage.dart';

class WebViewPage extends StatefulWidget {
  final String url;
  final VoidCallback onReset;
  const WebViewPage({super.key, required this.url, required this.onReset});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0A1222))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _loading = true;
            _error = null;
          }),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (err) {
            // Nur echte Seitenfehler zeigen, nicht jede Teilressource.
            if (err.isForMainFrame ?? true) {
              setState(() => _error = err.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _changeServer() async {
    await Storage.clear();
    widget.onReset();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('RIMPERIO'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Neu laden',
              onPressed: () => _controller.reload(),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'server') _changeServer();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'server', child: Text('Server ändern')),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_error == null) WebViewWidget(controller: _controller),
            if (_error != null) _ErrorView(message: _error!, onRetry: () {
              setState(() => _error = null);
              _controller.loadRequest(Uri.parse(widget.url));
            }, onChangeServer: _changeServer),
            if (_loading && _error == null)
              const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChangeServer;
  const _ErrorView({required this.message, required this.onRetry, required this.onChangeServer});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
            const SizedBox(height: 12),
            const Text('Server nicht erreichbar', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
                OutlinedButton(onPressed: onChangeServer, child: const Text('Server ändern')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
