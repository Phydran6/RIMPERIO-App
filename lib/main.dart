// ---------------------------------------------------------------------------
// Datei:        lib/main.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Einstieg. Je nach Sitzungszustand: Einrichtung → Anmeldung →
//               Sperrbildschirm (Biometrie) → App. Beim Zurückkehren nach
//               mehr als zwei Minuten im Hintergrund sperrt die App erneut.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/notifications.dart';
import 'core/session.dart';
import 'screens/home_page.dart';
import 'screens/lock_page.dart';
import 'screens/login_page.dart';
import 'screens/setup_page.dart';
import 'ui/scope.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');
  try {
    await Notifications.init();
  } catch (e) {
    debugPrint('Benachrichtigungen nicht verfügbar: $e');
  }
  final session = Session();
  runApp(RimperioApp(session: session));
  await session.start();
}

class RimperioApp extends StatefulWidget {
  final Session session;
  const RimperioApp({super.key, required this.session});

  @override
  State<RimperioApp> createState() => _RimperioAppState();
}

class _RimperioAppState extends State<RimperioApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) widget.session.paused();
    if (state == AppLifecycleState.resumed) widget.session.resumed();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: widget.session,
      child: MaterialApp(
        title: 'RIMPERIO',
        debugShowCheckedModeBanner: false,
        theme: RimTheme.dark(),
        locale: const Locale('de'),
        home: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) {
            final s = widget.session;
            final page = switch (s.stage) {
              Stage.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
              Stage.setup => const SetupPage(),
              Stage.login => const LoginPage(),
              Stage.locked => const LockPage(),
              Stage.ready => const HomePage(),
            };
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(key: ValueKey(s.stage), child: page),
            );
          },
        ),
      ),
    );
  }
}

