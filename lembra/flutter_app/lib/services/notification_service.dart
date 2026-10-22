import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/item.dart';
import 'alarme_nativo.dart';

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

  /// Chamado quando o usuário toca no alarme crítico (ou o app é aberto pela tela cheia).
  /// Recebe o id do item e o id da notificação (para poder silenciá-la).
  void Function(String itemId, int? notificacaoId)? aoAbrirAlarme;

  static const _idBriefing = 2147483000;
  static const _idRevisao = 2147483001;

  /// Canal novo: o Android não deixa mudar som/vibração de um canal já criado,
  /// então o alarme "de despertador" usa um id diferente do antigo 'lembretes_critico'.
  static const _canalAlarme = 'alarme_despertador';
  static const _prefixoAlarme = 'alarme:';
  static const _somAlarme = UriAndroidNotificationSound('content://settings/system/alarm_alert');

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
      onDidReceiveNotificationResponse: _tratarResposta,
    );

    AlarmeNativo.instance
      ..aoTocar = ((alarme) => aoAbrirAlarme?.call(alarme.itemId, null))
      ..iniciar();

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
    await a?.deleteNotificationChannel('lembretes_critico');
    await a?.createNotificationChannel(AndroidNotificationChannel(
      _canalAlarme,
      'Alarmes críticos',
      description: 'Alarme de despertador em tela cheia que repete até você confirmar',
      importance: Importance.max,
      playSound: true,
      sound: _somAlarme,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(<int>[0, 900, 500, 900, 500, 900]),
    ));
  }

  /// Toque na notificação ou em um botão. Alarmes críticos (payload "alarme:<id>")
  /// abrem a tela cheia; os botões e os demais avisos seguem o fluxo de sempre,
  /// recebendo o id do item como payload.
  void _tratarResposta(NotificationResponse r) {
    final bruto = r.payload;
    if (bruto != null && bruto.startsWith(_prefixoAlarme)) {
      final itemId = bruto.substring(_prefixoAlarme.length);
      final toque = r.notificationResponseType == NotificationResponseType.selectedNotification;
      if (toque && aoAbrirAlarme != null) {
        aoAbrirAlarme!(itemId, r.id);
      } else {
        aoResponder?.call(r.actionId, itemId);
      }
      return;
    }
    aoResponder?.call(r.actionId, bruto);
  }

  /// Silencia o alarme que está tocando: o som "insistente" só para quando a
  /// notificação é removida. Em itens recorrentes, cancelar o id também apaga a
  /// próxima repetição, então o item é reagendado em seguida.
  Future<void> pararAlarme({int? notificacaoId, Item? item}) async {
    await AlarmeNativo.instance.parar(); // som, vibração e tela do alarme nativo
    if (notificacaoId != null) await _plugin.cancel(notificacaoId);
    if (item != null && item.regra != null && !_usaNativo(item)) await agendarItem(item);
  }

  /// App aberto a partir de uma notificação (com o app fechado).
  Future<void> verificarLancamento() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    final r = d?.notificationResponse;
    if ((d?.didNotificationLaunchApp ?? false) && r != null) {
      _tratarResposta(r);
    }
    await verificarAlarmeTocando();
  }

  /// Há um alarme crítico tocando (serviço nativo)? Abre a tela cheia dele.
  /// Chamado ao abrir o app e sempre que ele volta ao primeiro plano.
  Future<void> verificarAlarmeTocando() async {
    final a = await AlarmeNativo.instance.atual();
    if (a != null) aoAbrirAlarme?.call(a.itemId, null);
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

  String _payload(Item item) => item.urgencia == Urgencia.critico ? '$_prefixoAlarme${item.id}' : item.id;

  /// Cada item usa até 8 ids consecutivos: base .. base+7 (o 7 é reservado à soneca).
  int _base(String id) => int.parse(id.substring(0, 7), radix: 16) * 8;

  /// No Android, alarmes críticos são agendados pelo serviço nativo (ver alarme_nativo.dart).
  bool _usaNativo(Item item) => item.urgencia == Urgencia.critico && AlarmeNativo.instance.disponivel;

  Future<void> cancelarItem(String id) async {
    await AlarmeNativo.instance.cancelarItem(id);
    final base = _base(id);
    for (var i = 0; i < 8; i++) {
      await _plugin.cancel(base + i);
    }
  }

  Future<void> cancelarTudo() async {
    await AlarmeNativo.instance.cancelarTudo();
    await _plugin.cancelAll();
  }

  /// (Re)agenda todos os avisos do item. Seguro de chamar várias vezes.
  Future<void> agendarItem(Item item) async {
    await cancelarItem(item.id);
    if (item.status != StatusItem.ativo) return;
    final ancora = item.ancora;
    if (ancora == null) return;

    final agora = DateTime.now();
    final base = _base(item.id);
    final payload = _payload(item);
    final detalhes = _detalhes(item.urgencia);
    final offsets = item.antecedencias.toSet().toList()..sort((a, b) => b.compareTo(a));
    final rec = item.regra;
    final nativo = _usaNativo(item);

    /// Um disparo: no Android, crítico vai para o serviço nativo; o resto, para o plugin.
    Future<void> emitir(
      int idx,
      String titulo,
      String corpo,
      DateTime quando, {
      DateTimeComponents? repetir,
      String? freq,
      int dia = 0,
      int diaMes = 0,
      int hora = 0,
      int minuto = 0,
    }) {
      if (nativo) {
        return AlarmeNativo.instance.agendar(
          chave: '${item.id}#$idx',
          itemId: item.id,
          titulo: titulo,
          corpo: corpo,
          quando: quando,
          freq: freq,
          dia: dia,
          diaMes: diaMes,
          hora: hora,
          minuto: minuto,
        );
      }
      return _agendar(base + idx, titulo, corpo, quando, detalhes, payload, repetir: repetir);
    }

    if (rec == null) {
      var idx = 0;
      for (final off in offsets) {
        if (idx >= 7) break;
        final quando = ancora.subtract(Duration(minutes: off));
        if (!quando.isAfter(agora)) continue;
        await emitir(idx, _titulo(item, off), _corpo(ancora, false), quando);
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
          await emitir(idx, _titulo(item, off), corpo, prox,
              repetir: DateTimeComponents.time, freq: 'DAILY', hora: t ~/ 60, minuto: t % 60);
          idx++;
        }
      case 'WEEKLY':
        // Um alarme por dia da semana, apenas no horário (sem antecedências).
        for (var k = 0; k < rec.dias.length && k < 7; k++) {
          final prox = rec.proximaDoDia(rec.dias[k], agora, h, m);
          if (prox == null) continue;
          await emitir(k, item.titulo, corpo, prox,
              repetir: DateTimeComponents.dayOfWeekAndTime, freq: 'WEEKLY', dia: rec.dias[k], hora: h, minuto: m);
        }
      case 'MONTHLY':
        final prox = rec.proxima(agora, h, m);
        if (prox != null) {
          await emitir(0, item.titulo, corpo, prox,
              repetir: DateTimeComponents.dayOfMonthAndTime, freq: 'MONTHLY', diaMes: rec.diaMes ?? 0, hora: h, minuto: m);
        }
    }
  }

  /// Aviso único daqui a [duracao] (soneca).
  Future<void> agendarSoneca(Item item, Duration duracao) async {
    final quando = DateTime.now().add(duracao);
    if (_usaNativo(item)) {
      await AlarmeNativo.instance.agendar(
        chave: '${item.id}#soneca',
        itemId: item.id,
        titulo: item.titulo,
        corpo: 'Adiado',
        quando: quando,
      );
      return;
    }
    await _agendar(_base(item.id) + 7, item.titulo, 'Adiado', quando, _detalhes(item.urgencia), _payload(item));
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
  }) async {
    final data = tz.TZDateTime.from(quando, tz.local);
    try {
      await _plugin.zonedSchedule(
        id,
        titulo,
        corpo,
        data,
        detalhes,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: repetir,
        payload: payload,
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
        payload: payload,
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
          android: AndroidNotificationDetails(
            _canalAlarme,
            'Alarmes críticos',
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            playSound: true,
            sound: _somAlarme,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: true,
            vibrationPattern: Int64List.fromList(<int>[0, 900, 500, 900, 500, 900]),
            visibility: NotificationVisibility.public,
            ongoing: true,
            autoCancel: false,
            additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT: repete o som até confirmar
            actions: _acoes,
          ),
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