import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/dinheiro.dart';
import '../domain/item.dart';

/// Exporta lembretes no formato .ics (iCalendar), aceito pelo Google Agenda,
/// Samsung Calendar, Outlook, Apple Calendar e outros.
class CalendarioIcs {
  static final _local = DateFormat("yyyyMMdd'T'HHmmss");
  static final _utc = DateFormat("yyyyMMdd'T'HHmmss'Z'");
  static final _dia = DateFormat('yyyyMMdd');

  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n');

  /// Linhas longas são dobradas, como manda o padrão.
  static String _dobrar(String linha) {
    final r = linha.runes.toList();
    if (r.length <= 60) return linha;
    final partes = <String>[String.fromCharCodes(r.sublist(0, 60))];
    for (var i = 60; i < r.length; i += 59) {
      final fim = i + 59 < r.length ? i + 59 : r.length;
      partes.add(' ${String.fromCharCodes(r.sublist(i, fim))}');
    }
    return partes.join('\r\n');
  }

    static List<String> _evento(Item i, String carimbo) {
    final ini = i.ancora;
    if (ini == null) return const [];
    // Sem horário definido (00:00) vira evento de dia inteiro.
    final diaInteiro = ini.hour == 0 && ini.minute == 0;
    final fim = ini.add(const Duration(minutes: 30));
    final proximoDia = DateTime(ini.year, ini.month, ini.day + 1);
    final desc = [
      i.tipo.rotulo,
      if (i.tipo == TipoItem.conta && i.valor != null) 'Valor: ${formatarReais(i.valor!)}',
    ].join(' • ');

    final linhas = <String>[
      'BEGIN:VEVENT',
      'UID:${i.id}@lembra.samsolution',
      'DTSTAMP:$carimbo',
      if (diaInteiro) ...[
        'DTSTART;VALUE=DATE:${_dia.format(ini)}',
        'DTEND;VALUE=DATE:${_dia.format(proximoDia)}',
      ] else ...[
        // Horário "flutuante": cada calendário usa o fuso do próprio aparelho.
        'DTSTART:${_local.format(ini)}',
        'DTEND:${_local.format(fim)}',
      ],
      'SUMMARY:${_esc(i.titulo)}',
      'DESCRIPTION:${_esc(desc)}',
    ];
    final rec = i.recorrencia?.replaceFirst(RegExp('^RRULE:', caseSensitive: false), '');
    if (rec != null && rec.isNotEmpty) linhas.add('RRULE:$rec');
    for (final min in i.antecedencias.toSet()) {
      // Dia inteiro: o aviso é contado a partir das 9h, não da meia-noite.
      final desloc = diaInteiro ? 540 - min : -min;
      linhas.addAll([
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${_esc(i.titulo)}',
        'TRIGGER:${desloc == 0 ? 'PT0S' : (desloc > 0 ? 'PT${desloc}M' : '-PT${-desloc}M')}',
        'END:VALARM',
      ]);
    }
    linhas.add('END:VEVENT');
    return linhas;
  }

  static String gerar(List<Item> itens) {
    final carimbo = _utc.format(DateTime.now().toUtc());
    final linhas = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Lembra//PT-BR//',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:Lembra',
      for (final i in itens) ..._evento(i, carimbo),
      'END:VCALENDAR',
    ];
    return '${linhas.map(_dobrar).join('\r\n')}\r\n';
  }

  /// Abre o menu de compartilhar com o arquivo .ics. Devolve quantos
  /// lembretes foram exportados (só os ativos e com data).
  static Future<int> compartilhar(List<Item> itens, {String nome = 'lembra'}) async {
    final ativos = itens.where((i) => i.status == StatusItem.ativo && i.ancora != null).toList();
    if (ativos.isEmpty) return 0;
    final dir = await getTemporaryDirectory();
    final arq = File('${dir.path}/$nome.ics');
    await arq.writeAsString(gerar(ativos));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(arq.path, mimeType: 'text/calendar')],
        subject: 'Lembretes do Lembra',
      ),
    );
    return ativos.length;
  }
}