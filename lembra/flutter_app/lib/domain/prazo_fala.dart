// Coloque em: lib/domain/prazo_fala.dart
//
// Fonte ÚNICA da verdade para "esse lembrete venceu? é hoje? é amanhã?" e para
// montar a frase que o app fala. Toda tela/serviço que fala ou mostra prazo
// deve passar por aqui, em vez de comparar datas por conta própria.
//
// Regra principal: com horário definido, o item está ATRASADO assim que
// `agora >= quando` (compara data E hora, não só o dia). Sem horário (item do
// dia inteiro), só fica atrasado quando o dia já passou.

import 'package:intl/intl.dart';

enum SituacaoPrazo { semData, atrasado, hoje, amanha, futuro }

class PrazoFala {
  PrazoFala._();

  /// Diferença em dias de calendário (ignora a hora). Negativo = passado.
  /// Usa UTC só para não sofrer com horário de verão.
  static int diasEntre(DateTime de, DateTime ate) {
    final a = DateTime.utc(de.year, de.month, de.day);
    final b = DateTime.utc(ate.year, ate.month, ate.day);
    return b.difference(a).inDays;
  }

  /// Classifica o prazo em relação a [agora].
  /// [temHorario] = false para itens do dia inteiro.
  static SituacaoPrazo situacao(
    DateTime? quando,
    DateTime agora, {
    bool temHorario = true,
  }) {
    if (quando == null) return SituacaoPrazo.semData;
    final dias = diasEntre(agora, quando);
    final vencido = temHorario ? !agora.isBefore(quando) : dias < 0;
    if (vencido) return SituacaoPrazo.atrasado;
    if (dias == 0) return SituacaoPrazo.hoje;
    if (dias == 1) return SituacaoPrazo.amanha;
    return SituacaoPrazo.futuro;
  }

  static String _plural(int n, String singular, String plural) =>
      '$n ${n == 1 ? singular : plural}';

  /// "23 minutos", "1 hora e 20 minutos", "2 dias".
  static String duracaoFalada(Duration d) {
    final min = d.inMinutes.abs();
    if (min < 1) return 'menos de um minuto';
    if (min < 60) return _plural(min, 'minuto', 'minutos');
    if (min < 60 * 24) {
      final h = min ~/ 60;
      final m = min % 60;
      final horas = _plural(h, 'hora', 'horas');
      return m == 0 ? horas : '$horas e ${_plural(m, 'minuto', 'minutos')}';
    }
    return _plural(d.inDays.abs(), 'dia', 'dias');
  }

  /// "17 horas e 7 minutos" (soa melhor no TTS do que "17:07").
  static String horaFalada(DateTime d) {
    final horas = _plural(d.hour, 'hora', 'horas');
    return d.minute == 0
        ? horas
        : '$horas e ${_plural(d.minute, 'minuto', 'minutos')}';
  }

  static String _as(DateTime d) =>
      '${d.hour == 1 ? 'à' : 'às'} ${horaFalada(d)}';

  static String _diaFalado(DateTime quando, DateTime agora) {
    final dias = diasEntre(agora, quando);
    if (dias == 0) return 'hoje';
    if (dias == -1) return 'ontem';
    if (dias == 1) return 'amanhã';
    return 'dia ${DateFormat("d 'de' MMMM", 'pt_BR').format(quando)}';
  }

  /// Frase falada para UM lembrete. Exemplos:
  ///  - "Pagar conta venceu às 17 horas e 7 minutos, há 23 minutos."
  ///  - "Pagar conta venceu ontem às 9 horas, há 1 dia."
  ///  - "Reunião é hoje às 18 horas, daqui a 1 hora e 20 minutos."
  ///  - "Dentista é amanhã às 10 horas."
  static String frase(
    String titulo,
    DateTime? quando,
    DateTime agora, {
    bool temHorario = true,
  }) {
    final s = situacao(quando, agora, temHorario: temHorario);
    if (quando == null || s == SituacaoPrazo.semData) {
      return '$titulo, sem horário definido.';
    }
    final dias = diasEntre(agora, quando);

    switch (s) {
      case SituacaoPrazo.atrasado:
        if (!temHorario) {
          return dias == -1
              ? '$titulo venceu ontem.'
              : '$titulo venceu há ${_plural(-dias, 'dia', 'dias')}.';
        }
        final quandoTxt =
            dias == 0 ? _as(quando) : '${_diaFalado(quando, agora)} ${_as(quando)}';
        return '$titulo venceu $quandoTxt, há ${duracaoFalada(agora.difference(quando))}.';

      case SituacaoPrazo.hoje:
        if (!temHorario) return '$titulo é para hoje.';
        final falta = quando.difference(agora);
        if (falta.inMinutes < 1) return '$titulo é agora.';
        return '$titulo é hoje ${_as(quando)}, daqui a ${duracaoFalada(falta)}.';

      case SituacaoPrazo.amanha:
        return temHorario
            ? '$titulo é amanhã ${_as(quando)}.'
            : '$titulo é amanhã.';

      case SituacaoPrazo.futuro:
        final dia = _diaFalado(quando, agora);
        return temHorario ? '$titulo é $dia ${_as(quando)}.' : '$titulo é $dia.';

      case SituacaoPrazo.semData:
        return '$titulo, sem horário definido.';
    }
  }
}