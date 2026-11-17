import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Toques disponíveis. Os nomes devem ser iguais aos arquivos em
/// android/app/src/main/res/raw/, sem a extensão .wav
class Toques {
  static const classico = 'alarme_classico';
  static const digital = 'alarme_digital';
  static const sino = 'alarme_sino';
  static const sirene = 'alarme_sirene';
  static const suave = 'alarme_suave';
  static const padrao = 'alarme';

  static const todos = [classico, digital, sino, sirene, suave, padrao];
}

class AlarmNotificationService {
  AlarmNotificationService._();
  static final instance = AlarmNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Um canal por toque. O Android só lê o som quando o canal é criado,
  /// então trocar de toque exige trocar de canal.
  static String canalDoToque(String som) => 'alarme_canal_$som';

  Future<void> init() async {
    tzdata.initializeTimeZones();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Cria um canal para cada toque.
    for (final som in Toques.todos) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          canalDoToque(som),
          'Alarme ($som)',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(som),
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
    }

    await _limparCanaisAntigos(android);
  }

  /// Remove canais antigos que ficaram salvos com o som errado.
  Future<void> _limparCanaisAntigos(
      AndroidFlutterLocalNotificationsPlugin? android) async {
    if (android == null) return;
    final validos = Toques.todos.map(canalDoToque).toSet();
    final existentes = await android.getNotificationChannels() ?? [];
    for (final c in existentes) {
      if (c.id.toLowerCase().contains('alarm') && !validos.contains(c.id)) {
        await android.deleteNotificationChannel(c.id);
      }
    }
  }

  /// Agenda (ou reagenda) um alarme.
  /// [id] deve ser SEMPRE o mesmo id do alarme no banco de dados.
  Future<void> agendar({
    required int id,
    required String titulo,
    required String corpo,
    required DateTime quando,
    required String som,
  }) async {
    // Cancela qualquer agendamento anterior com o mesmo id.
    await _plugin.cancel(id);

    if (quando.isBefore(DateTime.now())) return;

    final somValido = Toques.todos.contains(som) ? som : Toques.padrao;

    await _plugin.zonedSchedule(
      id,
      titulo,
      corpo,
      tz.TZDateTime.from(quando, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          canalDoToque(somValido),
          'Alarme ($somValido)',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(somValido),
          fullScreenIntent: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Use ao apagar ou desativar um alarme.
  Future<void> cancelar(int id) => _plugin.cancel(id);

  /// Use uma vez na inicialização antes de reagendar os alarmes do banco.
  Future<void> cancelarTodos() => _plugin.cancelAll();
}