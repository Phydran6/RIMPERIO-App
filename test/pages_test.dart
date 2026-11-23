// ---------------------------------------------------------------------------
// Datei:        test/pages_test.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.23.06.00.00
//
// Beschreibung: Die neuen Bereiche gegen einen simulierten Server: Logs
//               ansehen (ohne Info/Hinweis, Filter ohne „ab“), Logs suchen
//               (mit Info/Hinweis), Log-Bereich, Installieren-Reiter,
//               DB-Updates, Mehr-Seite. Prüft vor allem, dass nichts abstürzt
//               oder überläuft und die richtigen Anfragen rausgehen.
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rimperio_app/core/api.dart';
import 'package:rimperio_app/core/server_address.dart';
import 'package:rimperio_app/core/session.dart';
import 'package:rimperio_app/screens/db_updates_page.dart';
import 'package:rimperio_app/screens/log_hub_page.dart';
import 'package:rimperio_app/screens/logs_page.dart';
import 'package:rimperio_app/screens/patches_page.dart';
import 'package:rimperio_app/ui/scope.dart';
import 'package:rimperio_app/ui/theme.dart';

final requests = <Uri>[];

Map<String, dynamic> _log(int id, String level, String summary) => {
      'id': id,
      'ts': '2026-11-23T05:00:00',
      'host': 'srv1',
      'level': level,
      'source': 'sshd',
      'message': 'raw $id',
      'summary': summary,
      'category': 'auth',
      'category_label': 'Anmeldung',
      'has_hint': true,
      'repeat': id == 1 ? 12 : null,
    };

Object? _route(http.Request r) {
  final p = r.url.path;
  switch (p) {
    case '/api/app/logs':
      return {
        'items': [_log(1, 'critical', 'Arbeitsspeicher voll – Prozess java wurde beendet'), _log(2, 'warning', 'SSH-Anmeldung fehlgeschlagen')],
        'has_more': false,
        'next_before_id': null,
        'newest_id': 2,
      };
    case '/api/log-handling/overview':
      return {
        'tiers': {'debug': 1, 'info': 7, 'notice': 14, 'warning': 60, 'error': 180, 'critical': 365},
        'default_tiers': {'debug': 1, 'info': 7, 'notice': 14, 'warning': 60, 'error': 180, 'critical': 365},
        'global_days': 90,
        'dedup': {'enabled': true, 'window_seconds': 300},
        'rules': [],
        'last_24h': {'info': 120000, 'notice': 3000, 'warning': 12, 'error': 2},
      };
    case '/api/app/patching/open':
      return {
        'hosts': [
          {
            'agent_uid': 'u1', 'host': 'web01', 'platform': 'linux', 'online': true, 'snapshot_possible': true,
            'active_run': null, 'installable': 2, 'counts': {'approved': 1, 'auto': 1, 'needs_approval': 1},
            'items': [
              {'id': 1, 'title': 'openssl 3.0.15', 'kind': 'os', 'status': 'auto', 'status_label': 'automatisch',
               'installable': true, 'security': true, 'to': '3.0.15'},
              {'id': 2, 'title': 'db (postgres:16)', 'kind': 'docker', 'status': 'approved', 'status_label': 'freigegeben',
               'installable': true, 'db': true},
              {'id': 3, 'title': 'Kernel 6.1', 'kind': 'os', 'status': 'needs_approval', 'status_label': 'Freigabe nötig',
               'installable': false, 'reboot': true},
            ],
          },
        ],
        'totals': {'hosts': 1, 'installable': 2, 'needs_approval': 1, 'reviewing': 0},
      };
    case '/api/app/patching/approvals':
      return {'items': []};
    case '/api/app/patching/runs':
      return {'items': []};
    case '/api/db-updates':
      return {
        'candidates': [
          {'agent_uid': 'u1', 'hostname': 'web01', 'container': 'db-1', 'image': 'postgres:16', 'engine': 'postgres',
           'update_available': true, 'migration': null},
        ],
        'items': [
          {'id': 1, 'hostname': 'web01', 'container': 'db-1', 'status': 'awaiting_approval',
           'status_label': 'wartet auf Freigabe', 'old_version': '16.4', 'new_version': '17.2', 'can_approve': true},
        ],
      };
  }
  return {'detail': 'unbekannt'};
}

Session _session() {
  final client = MockClient((r) async {
    requests.add(r.url);
    final body = _route(r);
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
  });
  final s = Session();
  s.server = ServerAddress.parse('https://rmm.test');
  s.api = Api(s.server!, token: 'x', client: client);
  s.bootstrap = {
    'server': {
      'capabilities': ['log-handling', 'patch-installable', 'db-updates', 'patch-approvals', 'remote-console'],
      'version': 'test',
    },
    'user': {'username': 'admin', 'is_admin': true, 'role': 'admin'},
    'filters': {'hostnames': ['srv1', 'web01']},
  };
  return s;
}

Widget _wrap(Session s, Widget child) => SessionScope(
      session: s,
      child: MaterialApp(theme: RimTheme.dark(), home: child),
    );

void main() {
  setUp(requests.clear);

  testWidgets('Logs ansehen: ohne Info/Hinweis, Filter ohne „ab“', (t) async {
    await t.pumpWidget(_wrap(_session(), const Scaffold(body: LogsPage())));
    await t.pumpAndSettle();
    expect(find.text('Arbeitsspeicher voll – Prozess java wurde beendet'), findsOneWidget);
    expect(find.text('Kritisch'), findsOneWidget);
    expect(find.text('Fehler'), findsOneWidget);
    expect(find.text('Warnung'), findsOneWidget);
    expect(find.text('Info'), findsNothing);
    expect(find.text('Hinweis'), findsNothing);
    expect(find.textContaining('ab '), findsNothing);
    expect(find.text('×12'), findsOneWidget);
    final q = requests.firstWhere((u) => u.path == '/api/app/logs').queryParameters;
    expect(q['exclude_low'], 'true');

    await t.tap(find.text('Fehler'));
    await t.pumpAndSettle();
    final q2 = requests.lastWhere((u) => u.path == '/api/app/logs').queryParameters;
    expect(q2['levels'], 'error');
    expect(q2.containsKey('exclude_low'), isFalse);
  });

  testWidgets('Logs suchen: Info und Hinweis wählbar', (t) async {
    await t.pumpWidget(_wrap(_session(), const Scaffold(body: LogsPage(mode: LogMode.search, initialSearch: 'ssh'))));
    await t.pumpAndSettle();
    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Hinweis'), findsOneWidget);
    await t.tap(find.text('Info'));
    await t.pumpAndSettle();
    final q = requests.lastWhere((u) => u.path == '/api/app/logs').queryParameters;
    expect(q['levels'], 'info');
    expect(q['search'], 'ssh');
  });

  testWidgets('Log-Bereich zeigt alle Einstiege', (t) async {
    t.view.physicalSize = const Size(1080, 2600);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_session(), const LogHubPage()));
    await t.pumpAndSettle();
    for (final s in ['Logs ansehen', 'Logs suchen', 'Themenbereiche', 'Rauschen & Sperren', 'Sperrregeln', 'Aufbewahrung']) {
      expect(find.text(s), findsOneWidget);
    }
  });

  testWidgets('Installieren-Reiter: je Rechner und „Alle installieren“', (t) async {
    await t.pumpWidget(_wrap(_session(), const PatchesPage(initialTab: 1)));
    await t.pumpAndSettle();
    expect(find.text('web01'), findsOneWidget);
    expect(find.text('Alle installieren (2)'), findsOneWidget);
    expect(find.text('Installieren (2)'), findsOneWidget);
    expect(find.text('DB mit Probelauf'), findsOneWidget);
  });

  testWidgets('DB-Updates: Vorgang und Container', (t) async {
    await t.pumpWidget(_wrap(_session(), const DbUpdatesPage()));
    await t.pumpAndSettle();
    expect(find.text('web01 / db-1'), findsOneWidget);
    expect(find.text('Update prüfen'), findsOneWidget);
    expect(find.text('Freigabe'), findsOneWidget);
  });
}
