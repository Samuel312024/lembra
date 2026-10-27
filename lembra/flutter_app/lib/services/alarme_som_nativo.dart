import 'package:flutter/services.dart';
import 'alarm_notification.dart';

class AlarmeSomNativo {
  static const _canal = MethodChannel('lembra/alarme_som');

  static Future<void> tocar(SomAlarme som, {bool repetir = false}) async {
    try {
      await _canal.invokeMethod('tocar', {'recurso': som.recurso, 'uri': som.uri, 'repetir': repetir});
    } catch (_) {}
  }

  static Future<void> parar() async {
    try { await _canal.invokeMethod('parar'); } catch (_) {}
  }
}