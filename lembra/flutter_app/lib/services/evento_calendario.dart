// Coloque em: lib/services/evento_calendario.dart
//
// Fala com o calendário do celular sobre eventos que o Lembra criou:
//  - atualizar: título, horário, local/link e convidados (e-mail);
//  - excluir;
//  - lerRespostas: lê quem aceitou, recusou ou ainda não respondeu. O convite sai
//    pelo Google Agenda e a resposta volta pela sincronização da conta Google.
// Usa o device_calendar direto. Qualquer falha vira `false`/`null`: o app nunca
// quebra por causa do calendário.

import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/agendamento.dart' show RespostaConvite;

class EventoCalendario {
  EventoCalendario() : _plugin = DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;

  Future<Event?> _buscar(String calendarioId, String eventoId) async {
    final achados = await _plugin.retrieveEvents(
      calendarioId,
      RetrieveEventsParams(eventIds: [eventoId]),
    );
    final lista = achados.data;
    if (!achados.isSuccess || lista == null || lista.isEmpty) return null;
    return lista.first;
  }

  /// Atualiza título, horário e local/link. Relê o evento antes de salvar, para
  /// preservar o que o Lembra não mexe (lembretes, convidados existentes...).
  ///
  /// [adicionarConvidados]: e-mail (minúsculo) -> nome. Entram no evento e o
  /// Google Agenda envia o convite. [removerEmails]: e-mails (minúsculos) a tirar.
  Future<bool> atualizar({
    required String calendarioId,
    required String eventoId,
    required String titulo,
    required DateTime inicio,
    required DateTime fim,
    String? linkOuLocal,
    Map<String, String> adicionarConvidados = const {},
    Set<String> removerEmails = const {},
  }) async {
    try {
      final ev = await _buscar(calendarioId, eventoId);
      if (ev == null) return false;

      final texto = (linkOuLocal == null || linkOuLocal.trim().isEmpty) ? null : linkOuLocal.trim();
      ev.title = titulo;
      ev.start = tz.TZDateTime.from(inicio, tz.local);
      ev.end = tz.TZDateTime.from(fim, tz.local);
      ev.description = texto;
      ev.location = texto;

      if (adicionarConvidados.isNotEmpty || removerEmails.isNotEmpty) {
        final lista = <Attendee?>[...?ev.attendees];
        lista.removeWhere(
          (p) => p != null && removerEmails.contains((p.emailAddress ?? '').trim().toLowerCase()),
        );
        final existentes = {
          for (final p in lista)
            if (p != null) (p.emailAddress ?? '').trim().toLowerCase(),
        };
        adicionarConvidados.forEach((email, nome) {
          if (existentes.contains(email.trim().toLowerCase())) return;
          lista.add(Attendee(name: nome, emailAddress: email.trim(), role: AttendeeRole.Required));
        });
        ev.attendees = lista;
      }

      final r = await _plugin.createOrUpdateEvent(ev);
      return r?.isSuccess ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> excluir(String calendarioId, String eventoId) async {
    try {
      final r = await _plugin.deleteEvent(calendarioId, eventoId);
      return r.isSuccess && (r.data ?? false);
    } catch (_) {
      return false;
    }
  }

  /// Resposta de cada convidado do evento, por e-mail (minúsculo).
  /// Quem está na lista foi convidado pelo calendário; "pendente" = ainda não respondeu.
  /// Retorna null se não deu para ler o evento (sem permissão, evento apagado...).
  Future<Map<String, RespostaConvite>?> lerRespostas(String calendarioId, String eventoId) async {
    try {
      final ev = await _buscar(calendarioId, eventoId);
      if (ev == null) return null;
      final respostas = <String, RespostaConvite>{};
      for (final p in ev.attendees ?? const <Attendee?>[]) {
        final email = p?.emailAddress?.trim().toLowerCase();
        if (p == null || email == null || email.isEmpty) continue;
        final status = p.androidAttendeeDetails?.attendanceStatus?.name.toLowerCase();
        respostas[email] = switch (status) {
          'accepted' => RespostaConvite.aceito,
          'declined' => RespostaConvite.recusado,
          'tentative' => RespostaConvite.talvez,
          _ => RespostaConvite.pendente,
        };
      }
      return respostas;
    } catch (_) {
      return null;
    }
  }
}