// ---------------------------------------------------------------------------
// Datei:        lib/core/notifications.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.24.12.00.00
//
// Beschreibung: Benachrichtigungen. Der Server kennt keinen Push-Dienst — die
//               App fragt deshalb neue Meldungen ab, mit dem Geräteschlüssel
//               (/api/app/push, läuft nicht nach 24 h ab) bzw. ohne ihn mit der
//               Sitzung (/api/app/notifications?since_id=…):
//                 * im Vordergrund jede Minute,
//                 * im Hintergrund (Android, WorkManager) alle 15 Minuten —
//                   das ist das kürzeste, was Android erlaubt.
//               Neue Meldungen erscheinen als System-Benachrichtigung.
//               Die Berechtigung (Android 13+, iOS) wird einmal abgefragt.
//               Die Hintergrundabfrage prüft außerdem einmal am Tag, ob es
//               eine neue App-Version auf GitHub gibt (lib/core/app_update.dart),
//               und meldet sie einmal je Version.
// ---------------------------------------------------------------------------
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'app_update.dart';
import 'server_address.dart';
import 'storage.dart';

const _taskName = 'rimperio.poll';
const _channelId = 'rimperio_alerts';
const _updateChannelId = 'rimperio_app_update';
const _updateNotificationId = 0x52494D; // fest: neue Version ersetzt die alte Meldung

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
    try {
      await Notifications.checkAppUpdate();
    } catch (e) {
      debugPrint('App-Update-Prüfung fehlgeschlagen: $e');
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
    final deviceKey = await Storage.getDeviceKey();
    if (url == null || (token == null && deviceKey == null)) return 0;

    final api = Api(ServerAddress.parse(url), token: token);
    try {
      final last = await Storage.getLastNotificationId();
      // Mit Geräteschlüssel klappt das auch, wenn die 24-h-Sitzung abgelaufen
      // ist — genau dann kamen früher keine Benachrichtigungen mehr.
      final Map<String, dynamic> data;
      if (deviceKey != null) {
        try {
          data = await api.pushPoll(deviceKey, last, last == null ? 1 : 20);
        } on ApiException catch (e) {
          if (e.isUnauthorized) await Storage.setDevice(null, null); // widerrufen
          rethrow;
        }
      } else {
        data = await api.getJson('/api/app/notifications', {
          'since_id': last,
          'limit': last == null ? 1 : 20,
        });
      }
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

  /// Gerät beim Server für die Hintergrundabfrage anmelden (einmal je Anmeldung).
  static Future<void> registerDevice(Api api, {String name = 'Handy'}) async {
    if (await Storage.getDeviceKey() != null) return;
    try {
      final d = await api.postJson('/api/app/devices/register', {
        'name': name,
        'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
      });
      await Storage.setDevice(d['device_id'] as int?, d['device_key'] as String?);
    } catch (e) {
      debugPrint('Gerät nicht angemeldet: $e');
    }
  }

  /// Beim Abmelden: Schlüssel am Server widerrufen.
  static Future<void> unregisterDevice(Api? api) async {
    final id = await Storage.getDeviceId();
    if (api != null && id != null) {
      try {
        await api.delete('/api/app/devices/$id');
      } catch (_) {}
    }
    await Storage.setDevice(null, null);
  }

  /// Tägliche Prüfung auf eine neue App-Version; meldet jede Version einmal.
  static Future<void> checkAppUpdate() async {
    if (!await Storage.getNotify()) return;
    final r = await AppUpdate.autoCheck();
    if (r == null) return;
    await init();
    await _plugin.show(
      id: _updateNotificationId,
      title: 'RIMPERIO-App ${r.version} ist da',
      body: 'Mehr → App-Update: per Knopfdruck installieren.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _updateChannelId,
          'App-Updates',
          channelDescription: 'Neue Version der RIMPERIO-App auf GitHub',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    await AppUpdate.markNotified(r);
  }

  /// Prüft den ganzen Weg: Berechtigung, Anzeige auf dem Handy, Abfrage beim
  /// Server (mit Geräteschlüssel). Gibt eine Meldung für die Oberfläche zurück.
  static Future<String> test() async {
    await init();
    if (!await permitted()) return 'Benachrichtigungen sind für RIMPERIO in den Systemeinstellungen blockiert.';
    await _show({
      'id': DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      'title': 'RIMPERIO: Test',
      'body': 'So sehen Meldungen vom Server aus.',
      'level': 'info',
    });
    final key = await Storage.getDeviceKey();
    final url = await Storage.getUrl();
    if (url == null) return 'Test angezeigt.';
    final api = Api(ServerAddress.parse(url), token: await Storage.getToken());
    try {
      if (key != null) {
        await api.pushPoll(key, await Storage.getLastNotificationId(), 1);
        return 'Test angezeigt. Hintergrundabfrage mit Geräteschlüssel funktioniert.';
      }
      return 'Test angezeigt. Kein Geräteschlüssel – Meldungen kommen nur, solange die Anmeldung gilt (24 h).';
    } on ApiException catch (e) {
      return 'Test angezeigt, aber die Abfrage beim Server scheitert: ${e.message}';
    } catch (e) {
      return 'Test angezeigt, aber der Server ist nicht erreichbar: $e';
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
