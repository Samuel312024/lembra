import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/reuniao.dart';
import 'leitor_link_reuniao.dart';

/// Lê e grava reuniões no calendário do aparelho (Google, Outlook, Exchange...).
///
/// Pré-requisito no main(): chamar `tz.initializeTimeZones()` e
/// `tz.setLocalLocation(...)` (use o pacote flutter_timezone para obter o fuso).
class CalendarioService {
  CalendarioService({DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;

  Future<bool> temPermissao() async {
    final r = await _plugin.hasPermissions();
    return r.isSuccess && (r.data ?? false);
  }

  Future<bool> pedirPermissao() async {
    if (await temPermissao()) return true;
    final r = await _plugin.requestPermissions();
    return r.isSuccess && (r.data ?? false);
  }

  Future<List<Calendar>> listarCalendarios() async {
    final r = await _plugin.retrieveCalendars();
    if (!r.isSuccess || r.data == null) return const [];
    return r.data!.toList();
  }

  /// Calendários onde o app pode criar reuniões.
  Future<List<Calendar>> listarCalendariosEditaveis() async {
    final todos = await listarCalendarios();
    return todos.where((c) => c.isReadOnly == false).toList();
  }

  /// Reuniões dos próximos [dias]: eventos com link de videoconferência
  /// ou com mais de um participante. Remove duplicados entre calendários.
  Future<List<Reuniao>> listarReunioes({
    DateTime? aPartirDe,
    int dias = 14,
    Set<String>? calendariosIds,
  }) async {
    final inicio = aPartirDe ?? DateTime.now();
    final fim = inicio.add(Duration(days: dias));
    final vistas = <String>{};
    final reunioes = <Reuniao>[];

    for (final cal in await listarCalendarios()) {
      final calId = cal.id;
      if (calId == null) continue;
      if (calendariosIds != null && !calendariosIds.contains(calId)) continue;

      final r = await _plugin.retrieveEvents(
        calId,
        RetrieveEventsParams(startDate: inicio, endDate: fim),
      );
      if (!r.isSuccess || r.data == null) continue;

      for (final e in r.data!) {
        if (e.start == null || e.end == null) continue;
        final link = LeitorLinkReuniao.extrair(
          [e.description, e.location, e.url?.toString()],
        );
        final emails = (e.attendees ?? [])
            .map((a) => a?.emailAddress)
            .whereType<String>()
            .toList();
        if (link == null && emails.length < 2) continue;

        final ini = DateTime.fromMillisecondsSinceEpoch(
            e.start!.millisecondsSinceEpoch);
        final chave = '${e.title}|${ini.toIso8601String()}|${link?.url}';
        if (!vistas.add(chave)) continue;

        reunioes.add(Reuniao(
          id: e.eventId ?? chave,
          calendarioId: calId,
          calendarioNome: cal.accountName ?? cal.name ?? '',
          titulo: e.title ?? 'Sem título',
          inicio: ini,
          fim: DateTime.fromMillisecondsSinceEpoch(
              e.end!.millisecondsSinceEpoch),
          local: e.location,
          link: link,
          participantes: emails,
          diaInteiro: e.allDay ?? false,
        ));
      }
    }
    reunioes.sort((a, b) => a.inicio.compareTo(b.inicio));
    return reunioes;
  }

  /// Cria a reunião no calendário escolhido. Chamar somente depois que o
  /// usuário confirmar no cartão de confirmação (nada é agendado sem confirmar).
  /// Devolve o id do evento criado, ou null em caso de falha.
  Future<String?> criarReuniao({
    required String calendarioId,
    required String titulo,
    required DateTime inicio,
    required DateTime fim,
    String? descricao,
    String? local,
    List<String> participantes = const [],
  }) async {
    final evento = Event(
      calendarioId,
      title: titulo,
      start: tz.TZDateTime.from(inicio, tz.local),
      end: tz.TZDateTime.from(fim, tz.local),
      description: descricao,
      attendees: participantes
          .map((e) => Attendee(emailAddress: e, role: AttendeeRole.Required))
          .toList(),
    );
    evento.location = local;
    final r = await _plugin.createOrUpdateEvent(evento);
    return (r != null && r.isSuccess) ? r.data : null;
  }
}