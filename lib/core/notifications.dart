// ---------------------------------------------------------------------------
// Datei:        lib/core/notifications.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Benachrichtigungen. Der Server kennt keinen Push-Dienst — die
//               App fragt deshalb /api/app/notifications?since_id=… ab:
//                 * im Vordergrund jede Minute,
//                 * im Hintergrund (Android, WorkManager) alle 15 Minuten —
//                   das ist das kürzeste, was Android erlaubt.
//               Neue Meldungen erscheinen als System-Benachrichtigung.
//               Die Berechtigung (Android 13+, iOS) wird einmal abgefragt.
// ---------------------------------------------------------------------------
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'server_address.dart';
import 'storage.dart';

const _taskName = 'rimperio.poll';
const _channelId = 'rimperio_alerts';

final _plugin = FlutterLocalNotificationsPlugin();
bool _initialized = false;

/// Läuft in einem eigenen Isolate, wenn WorkManager die App weckt.
@pragma('vm:entry-point')
void notificationDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Notifications.poll(background: true);
    } catch (e) {
      debugPrint('Hintergrundabfrage fehlgeschlagen: $e');
    }
    return true; // Nie "Fehler" melden — sonst stapelt Android Wiederholungen.
  });
}

class Notifications {
  static Future<void> init() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Berechtigung erst nach der Anmeldung fragen, nicht beim Start.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  /// Fragt die Berechtigung an. `true`, wenn Benachrichtigungen erlaubt sind.
  static Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  static Future<bool> permitted() async {
    await init();
    if (Platform.isAndroid) {
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final s = await ios?.checkPermissions();
      return s?.isEnabled ?? false;
    }
    return false;
  }

  /// Hintergrundabfrage an- oder abmelden.
  static Future<void> schedule(bool on) async {
    if (!Platform.isAndroid) return; // iOS: nur im Vordergrund (kein Push-Dienst).
    await Workmanager().initialize(notificationDispatcher);
    if (on) {
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(_taskName);
    }
  }

  /// Neue Meldungen holen und anzeigen. Beim ersten Mal wird nur der Stand
  /// gemerkt — sonst käme nach der Anmeldung eine Flut alter Meldungen.
  static Future<int> poll({bool background = false}) async {
    if (!await Storage.getNotify()) return 0;
    final url = await Storage.getUrl();
    final token = await Storage.getToken();
    if (url == null || token == null) return 0;

    final api = Api(ServerAddress.parse(url), token: token);
    try {
      final last = await Storage.getLastNotificationId();
      final data = await api.getJson('/api/app/notifications', {
        'since_id': last,
        'limit': last == null ? 1 : 20,
      });
      final items = (data['items'] as List).cast<Map<String, dynamic>>();
      final newest = data['newest_id'];
      if (newest is int) await Storage.setLastNotificationId(newest);
      if (last == null) return 0;

      await init();
      for (final n in items.reversed.take(5)) {
        await _show(n);
      }
      return items.length;
    } on ApiException catch (e) {
      // Abgelaufene Sitzung im Hintergrund: still bleiben, die App meldet sich
      // beim nächsten Öffnen selbst.
      if (!e.isUnauthorized) rethrow;
      return 0;
    } finally {
      api.close();
    }
  }

  static Future<void> _show(Map<String, dynamic> n) async {
    final level = n['level'] as String? ?? 'info';
    await _plugin.show(
      id: (n['id'] as int?) ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: n['title'] as String? ?? 'RIMPERIO',
      body: n['body'] as String? ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Meldungen',
          channelDescription: 'Freigaben, Fehlschläge und Alarme vom RIMPERIO-Server',
          importance: level == 'critical' ? Importance.max : Importance.high,
          priority: level == 'critical' ? Priority.max : Priority.high,
          category: AndroidNotificationCategory.status,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
