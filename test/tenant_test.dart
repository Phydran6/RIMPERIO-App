// ---------------------------------------------------------------------------
// Datei:        test/tenant_test.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.27.22.00.00
//
// Beschreibung: Mandanten aus /api/app/bootstrap: Betreiber vs. Kunden-Konto,
//               Ansicht umschalten (Kopf X-Rimperio-Tenant).
// ---------------------------------------------------------------------------
import 'package:flutter_test/flutter_test.dart';
import 'package:rimperio_app/core/api.dart';
import 'package:rimperio_app/core/server_address.dart';
import 'package:rimperio_app/core/session.dart';

void main() {
  test('Betreiber: Mandanten an, Liste und Ansicht', () {
    final s = Session()
      ..api = Api(ServerAddress.parse('https://rmm.test'))
      ..bootstrap = {
        'tenancy': {
          'enabled': true,
          'is_provider': true,
          'tenant': null,
          'tenants': [
            {'id': 3, 'name': 'Müller GmbH', 'slug': 'mueller-gmbh'},
          ],
        },
      };
    expect(s.tenancyEnabled, isTrue);
    expect(s.isProvider, isTrue);
    expect(s.ownTenantName, isNull);
    expect(s.tenants.single['name'], 'Müller GmbH');
    expect(s.tenantScopeLabel, 'Alle Mandanten');
    s.api!.tenantScope = '3';
    expect(s.tenantScopeLabel, 'Müller GmbH');
    s.api!.tenantScope = '0';
    expect(s.tenantScopeLabel, 'Nur Betreiber');
  });

  test('Kunden-Konto: eigener Mandant, kein Umschalten', () {
    final s = Session()
      ..bootstrap = {
        'tenancy': {
          'enabled': true,
          'is_provider': false,
          'tenant': {'id': 3, 'name': 'Müller GmbH', 'slug': 'mueller-gmbh'},
          'tenants': [],
        },
      };
    expect(s.isProvider, isFalse);
    expect(s.ownTenantName, 'Müller GmbH');
    expect(s.tenants, isEmpty);
  });

  test('Älterer Server ohne Mandanten: alles wie bisher', () {
    final s = Session()..bootstrap = {'server': {'capabilities': []}};
    expect(s.tenancyEnabled, isFalse);
    expect(s.isProvider, isTrue);
  });
}
