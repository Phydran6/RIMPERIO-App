// ---------------------------------------------------------------------------
// Datei:        test/widget_test.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.06.23.30.00
//
// Beschreibung: Prüft die Einrichtungsseite: Logo da, leere oder kaputte
//               Adressen werden abgewiesen, ohne etwas zu speichern.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rimperio_app/setup_page.dart';

void main() {
  Future<void> pumpSetup(WidgetTester tester, List<String> saved) {
    return tester.pumpWidget(MaterialApp(home: SetupPage(onSaved: saved.add)));
  }

  testWidgets('zeigt Logo und Eingabefeld', (tester) async {
    await pumpSetup(tester, []);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.semanticLabel == 'RIMPERIO'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('leere Adresse wird abgewiesen', (tester) async {
    final saved = <String>[];
    await pumpSetup(tester, saved);
    await tester.tap(find.text('Verbinden'));
    await tester.pump();
    expect(find.text('Bitte eine Server-Adresse eingeben.'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('ungültige Adresse wird abgewiesen', (tester) async {
    final saved = <String>[];
    await pumpSetup(tester, saved);
    await tester.enterText(find.byType(TextField), 'https://');
    await tester.tap(find.text('Verbinden'));
    await tester.pump();
    expect(find.text('Die Adresse sieht nicht gültig aus.'), findsOneWidget);
    expect(saved, isEmpty);
  });
}
