// ---------------------------------------------------------------------------
// Datei:        lib/ui/scope.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Macht die Sitzung überall per `context.session` erreichbar.
// ---------------------------------------------------------------------------
import 'package:flutter/widgets.dart';

import '../core/session.dart';

class SessionScope extends InheritedWidget {
  final Session session;
  const SessionScope({super.key, required this.session, required super.child});

  @override
  bool updateShouldNotify(SessionScope oldWidget) => session != oldWidget.session;
}

extension SessionX on BuildContext {
  Session get session => dependOnInheritedWidgetOfExactType<SessionScope>()!.session;
}
