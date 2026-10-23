import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/item.dart';
import 'alarm_notification.dart';

/// Agenda lembretes e alarmes locais (funcionam com o app fechado e sem internet).
///
/// Garantias por plataforma:
///  - Android: alarme exato + tela cheia no nível "crítico" (exige permissões
///    de alarme exato e de tela cheia, pedidas de forma guiada nos Ajustes).
///  - iOS: não existe alarme em segundo plano para apps comuns; usamos
///    notificações locais com som e prioridade "time-sensitive".
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// (acao, payload) — chamado quando o usuário toca na notificação ou em um botão.
  void Function(String? acao, String? payload)? aoResponder;

  /// (idDoItem, idDaNotificação) — pede para mostrar o alarme crítico em tela
  /// cheia. Quem define é o app.dart, que abre a AlarmPage.
  void Function(String itemId, int? notificacaoId)? aoAbrirAlarme;

  static const _prefixoAlarme = 'alarme:';
  static const _chaveSom = 'som_alarme';

  /// Som do alarme crítico escolhido em Ajustes (padrão: alarme do celular).
  SomAlarme _somAlarme = sonsAlarme.first;
  SomAlarme get somAlarme => _somAlarme;

  static const _idBriefing = 2147483000;
  static const _idRevisao = 2147483001;
  static const _idTesteSom = 2147483002;

  static const _acoes = [
    AndroidNotificationAction('feito', 'Feito', showsUserInterface: true, cancelNotification: true),
    AndroidNotificationAction('soneca', 'Adiar 10 min',
        showsUserInterface: true, cancelNotification: true),
  ];

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final nome = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(nome.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _aoReceberResposta,
    );

    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await a?.createNotificationChannel(const AndroidNotificationChannel(
      'lembretes_discreto',
      'Lembretes discretos',
      description: 'Notificação silenciosa',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ));
    await a?.createNotificationChannel(const AndroidNotificationChannel(
      'lembretes_normal',
      'Lembretes',
      description: 'Notificação com som',
      importance: Importance.high,
    ));
    // Canal do alarme crítico: um por som (ver alarm_notification.dart).
    final prefs = await SharedPreferences.getInstance();
    _somAlarme = somAlarmePorId(prefs.getString(_chaveSom));
    await prepararCanalAlarme(_plugin, _somAlarme);
  }

  /// App aberto a partir de uma notificação (com o app fechado).
  Future<void> verificarLancamento() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    final r = d?.notificationResponse;
    if ((d?.didNotificationLaunchApp ?? false) && r != null) {
      _aoReceberResposta(r);
    }
  }

  // ---------- alarme em tela cheia ----------

  /// Ponto único de entrada: toque na notificação, botão da notificação ou
  /// abertura do app pela tela cheia do alarme.
  void _aoReceberResposta(NotificationResponse r) {
    final alarme = _lerAlarme(r.payload);
    if (alarme == null) {
      aoResponder?.call(r.actionId, r.payload);
      return;
    }
    final acao = r.actionId;
    if (acao != null && acao.isNotEmpty) {
      // Botão da notificação: o handler do app espera o id do item como payload.
      aoResponder?.call(acao, alarme.itemId);
      return;
    }
    final abrir = aoAbrirAlarme;
    if (abrir != null) {
      abrir(alarme.itemId, alarme.notifId);
    } else {
      aoResponder?.call(null, alarme.itemId); // sem tela de alarme: abre o item
    }
  }

  /// Para o som do alarme (cancela a notificação insistente). Alarmes
  /// recorrentes são reagendados em seguida, para não perder os próximos.
  Future<void> pararAlarme({int? notificacaoId, Item? item}) async {
    if (notificacaoId != null) {
      await _plugin.cancel(notificacaoId);
    } else if (item != null) {
      await cancelarItem(item.id);
    }
    if (item != null && item.regra != null) await agendarItem(item);
  }

  /// Troca o som do alarme crítico. Quem chama precisa reagendar os alarmes
  /// (eles passam a usar o canal do novo som).
  Future<void> definirSom(SomAlarme som) async {
    _somAlarme = som;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveSom, som.id);
    await prepararCanalAlarme(_plugin, som);
  }

  /// Toca o som escolhido uma vez (notificação curta, some sozinha).
  Future<void> testarSom() => _plugin.show(
        _idTesteSom,
        'Teste de som',
        _somAlarme.rotulo,
        NotificationDetails(android: detalhesAndroidAlarme(_somAlarme, insistente: false)),
      );

  String _codificarAlarme(int notifId, String itemId) =>
      '$_prefixoAlarme${jsonEncode({'n': notifId, 'i': itemId})}';

  _DadosAlarme? _lerAlarme(String? payload) {
    if (payload == null || !payload.startsWith(_prefixoAlarme)) return null;
    try {
      final m = jsonDecode(payload.substring(_prefixoAlarme.length)) as Map<String, dynamic>;
      return _DadosAlarme(notifId: (m['n'] as num).toInt(), itemId: m['i'] as String);
    } catch (_) {
      return null;
    }
  }

  // ---------- permissões ----------

  Future<bool> pedirPermissoes() async {
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final i = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    var ok = true;
    if (a != null) {
      ok = (await a.requestNotificationsPermission()) ?? false;
      await a.requestExactAlarmsPermission();
      await a.requestFullScreenIntentPermission();
    }
    if (i != null) {
      ok = (await i.requestPermissions(alert: true, badge: true, sound: true)) ?? false;
    }
    return ok;
  }

  Future<({bool notificacoes, bool alarmeExato})> estadoPermissoes() async {
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final i = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (a != null) {
      return (
        notificacoes: (await a.areNotificationsEnabled()) ?? false,
        alarmeExato: (await a.canScheduleExactNotifications()) ?? false,
      );
    }
    if (i != null) {
      return (notificacoes: (await i.checkPermissions())?.isEnabled ?? false, alarmeExato: true);
    }
    return (notificacoes: true, alarmeExato: true);
  }

  // ---------- agendamento ----------

  /// Cada item usa até 8 ids consecutivos: base .. base+7 (o 7 é reservado à soneca).
  int _base(String id) => int.parse(id.substring(0, 7), radix: 16) * 8;

  Future<void> cancelarItem(String id) async {
    final base = _base(id);
    for (var i = 0; i < 8; i++) {
      await _plugin.cancel(base + i);
    }
  }

  Future<void> cancelarTudo() => _plugin.cancelAll();

  /// (Re)agenda todos os avisos do item. Seguro de chamar várias vezes.
  Future<void> agendarItem(Item item) async {
    await cancelarItem(item.id);
    if (item.status != StatusItem.ativo) return;
    final ancora = item.ancora;
    if (ancora == null) return;

    final agora = DateTime.now();
    final base = _base(item.id);
    final detalhes = _detalhes(item.urgencia);
    final critico = item.urgencia == Urgencia.critico;
    final offsets = item.antecedencias.toSet().toList()..sort((a, b) => b.compareTo(a));
    final rec = item.regra;

    if (rec == null) {
      var idx = 0;
      for (final off in offsets) {
        if (idx >= 7) break;
        final quando = ancora.subtract(Duration(minutes: off));
        if (!quando.isAfter(agora)) continue;
        await _agendar(base + idx, _titulo(item, off), _corpo(ancora, false), quando, detalhes, item.id,
            alarme: critico);
        idx++;
      }
      return;
    }

    final h = ancora.hour;
    final m = ancora.minute;
    final minutosDoDia = h * 60 + m;
    final corpo = _corpo(ancora, true);
    switch (rec.freq) {
      case 'DAILY':
        var idx = 0;
        for (final off in offsets) {
          if (off > minutosDoDia || idx >= 7) continue; // avisos que cruzam a meia-noite não são repetidos
          final t = minutosDoDia - off;
          final prox = rec.proxima(agora, t ~/ 60, t % 60);
          if (prox == null) continue;
          await _agendar(base + idx, _titulo(item, off), corpo, prox, detalhes, item.id,
              repetir: DateTimeComponents.time, alarme: critico);
          idx++;
        }
      case 'WEEKLY':
        // Um alarme por dia da semana, apenas no horário (sem antecedências).
        for (var k = 0; k < rec.dias.length && k < 7; k++) {
          final prox = rec.proximaDoDia(rec.dias[k], agora, h, m);
          if (prox == null) continue;
          await _agendar(base + k, item.titulo, corpo, prox, detalhes, item.id,
              repetir: DateTimeComponents.dayOfWeekAndTime, alarme: critico);
        }
      case 'MONTHLY':
        final prox = rec.proxima(agora, h, m);
        if (prox != null) {
          await _agendar(base, item.titulo, corpo, prox, detalhes, item.id,
              repetir: DateTimeComponents.dayOfMonthAndTime, alarme: critico);
        }
    }
  }

  /// Aviso único daqui a [duracao] (soneca).
  Future<void> agendarSoneca(Item item, Duration duracao) async {
    final quando = DateTime.now().add(duracao);
    await _agendar(_base(item.id) + 7, item.titulo, 'Adiado', quando, _detalhes(item.urgencia), item.id,
        alarme: item.urgencia == Urgencia.critico);
  }

  /// Briefing da manhã e revisão da noite: notificações diárias fixas.
  Future<void> atualizarRotinas({
    required bool briefing,
    required int briefingMin,
    required bool revisao,
    required int revisaoMin,
  }) async {
    await _diaria(_idBriefing, briefing, briefingMin, 'Bom dia!', 'Toque para ver e ouvir o resumo do seu dia.', 'briefing');
    await _diaria(_idRevisao, revisao, revisaoMin, 'Revisão da noite', 'Veja o que ficou pendente e reagende em um toque.', 'revisao');
  }

  Future<void> _diaria(int id, bool ativo, int minutos, String titulo, String corpo, String payload) async {
    await _plugin.cancel(id);
    if (!ativo) return;
    final agora = DateTime.now();
    var quando = DateTime(agora.year, agora.month, agora.day, minutos ~/ 60, minutos % 60);
    if (!quando.isAfter(agora)) quando = DateTime(quando.year, quando.month, quando.day + 1, minutos ~/ 60, minutos % 60);
    await _agendar(id, titulo, corpo, quando, _detalhes(Urgencia.normal), payload,
        repetir: DateTimeComponents.time);
  }

  Future<void> _agendar(
    int id,
    String titulo,
    String corpo,
    DateTime quando,
    NotificationDetails detalhes,
    String payload, {
    DateTimeComponents? repetir,
    bool alarme = false,
  }) async {
    final data = tz.TZDateTime.from(quando, tz.local);
    // Alarmes críticos levam o id da notificação no payload; a tela cheia busca
    // o resto (título, mensagem) no item.
    final carga = alarme ? _codificarAlarme(id, payload) : payload;
    try {
      await _plugin.zonedSchedule(
        id,
        titulo,
        corpo,
        data,
        detalhes,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: repetir,
        payload: carga,
      );
    } on PlatformException {
      // Sem permissão de alarme exato: cai para o agendamento aproximado.
      await _plugin.zonedSchedule(
        id,
        titulo,
        corpo,
        data,
        detalhes,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: repetir,
        payload: carga,
      );
    }
  }

  NotificationDetails _detalhes(Urgencia u) {
    switch (u) {
      case Urgencia.discreto:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'lembretes_discreto',
            'Lembretes discretos',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            actions: _acoes,
          ),
          iOS: DarwinNotificationDetails(presentSound: false, interruptionLevel: InterruptionLevel.passive),
        );
      case Urgencia.normal:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'lembretes_normal',
            'Lembretes',
            importance: Importance.high,
            priority: Priority.high,
            actions: _acoes,
          ),
          iOS: DarwinNotificationDetails(presentSound: true, interruptionLevel: InterruptionLevel.active),
        );
      case Urgencia.critico:
        return NotificationDetails(
          android: detalhesAndroidAlarme(_somAlarme, acoes: _acoes),
          iOS: const DarwinNotificationDetails(
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        );
    }
  }

  String _titulo(Item item, int off) => off == 0 ? item.titulo : '${_antes(off)}: ${item.titulo}';

  String _antes(int off) {
    if (off >= 1440 && off % 1440 == 0) return 'Em ${off ~/ 1440} dia${off ~/ 1440 > 1 ? 's' : ''}';
    if (off >= 60 && off % 60 == 0) return 'Em ${off ~/ 60} h';
    return 'Em $off min';
  }

  String _corpo(DateTime ancora, bool recorrente) {
    if (recorrente) return 'Às ${DateFormat.Hm('pt_BR').format(ancora)}';
    return DateFormat("EEE, d 'de' MMM 'às' HH:mm", 'pt_BR').format(ancora);
  }
}

/// O que um alarme crítico carrega no payload da notificação.
class _DadosAlarme {
  const _DadosAlarme({required this.notifId, required this.itemId});

  final int notifId;
  final String itemId;
}