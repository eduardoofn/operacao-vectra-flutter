import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Avisos no celular quando entra chamado novo na fila.
/// Funciona com o app aberto ou em segundo plano recente, sem internet,
/// porque é notificação local e não push.
class Avisos {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _pronto = false;

  static Future<void> iniciar() async {
    if (_pronto) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    try {
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _pronto = true;
    } catch (e) {
      debugPrint('Notificações indisponíveis: $e');
    }
  }

  static Future<void> mostrar(int id, String titulo, String texto) async {
    if (!_pronto) return;
    const detalhes = NotificationDetails(
      android: AndroidNotificationDetails(
        'chamados',
        'Chamados de manutenção',
        channelDescription: 'Avisa quando entra um chamado novo na fila',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    try {
      await _plugin.show(id, titulo, texto, detalhes);
    } catch (e) {
      debugPrint('Falha ao avisar: $e');
    }
  }
}
