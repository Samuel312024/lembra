// Coloque em: lib/services/convite_service.dart
//
// Monta a mensagem do convite e abre o WhatsApp ou o app de e-mail já com o
// texto pronto. O app não consegue ler a resposta sozinho: quem responde manda
// SIM / NÃO / TALVEZ e o usuário registra a resposta no cartão da reunião.

import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/agendamento.dart';

class ConviteService {
  const ConviteService._();

  static String _dia(DateTime d) =>
      toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d)) ?? '';

  /// WhatsApp aceita *negrito*; no e-mail os asteriscos ficariam aparecendo.
  static String _n(String texto, bool whatsapp) => whatsapp ? '*$texto*' : texto;

  static String _detalhes(Agendamento a, bool whatsapp) {
    final hm = DateFormat.Hm('pt_BR');
    final b = StringBuffer()
      ..writeln('📅 ${_n(a.titulo, whatsapp)}')
      ..writeln('🗓️ ${_dia(a.inicio)}')
      ..write('🕒 ${hm.format(a.inicio)} às ${hm.format(a.fim)}');
    final onde = a.linkOuLocal?.trim() ?? '';
    if (onde.isNotEmpty) {
      b.write(detectarLink(onde) != null ? '\n🔗 $onde' : '\n📍 $onde');
    }
    return b.toString();
  }

  /// Convite inicial. Sem [para], gera um texto genérico (para copiar e colar).
  static String mensagemConvite(Agendamento a, {Convidado? para}) {
    final wa = para == null || para.canal == CanalConvite.whatsapp;
    final saudacao = para == null ? 'Olá!' : 'Olá, ${para.primeiroNome}!';
    return '$saudacao Você foi convidado(a) para uma reunião:\n\n'
        '${_detalhes(a, wa)}\n\n'
        'Pode confirmar sua presença? Responda ${_n('SIM', wa)}, ${_n('NÃO', wa)} ou ${_n('TALVEZ', wa)}.';
  }

  /// Segundo toque, para quem ainda não respondeu.
  static String mensagemLembrete(Agendamento a, Convidado para) {
    final wa = para.canal == CanalConvite.whatsapp;
    final hm = DateFormat.Hm('pt_BR');
    return 'Olá, ${para.primeiroNome}! Só passando para lembrar de confirmar sua presença em '
        '${_n(a.titulo, wa)}, ${_dia(a.inicio)} às ${hm.format(a.inicio)}.\n\n'
        'Pode responder ${_n('SIM', wa)}, ${_n('NÃO', wa)} ou ${_n('TALVEZ', wa)}?';
  }

  /// Link que abre a conversa já com o texto. Null se o contato for inválido.
  static Uri? urlPara(Agendamento a, Convidado c, {required bool lembrete}) {
    final texto = lembrete ? mensagemLembrete(a, c) : mensagemConvite(a, para: c);
    if (c.canal == CanalConvite.email) {
      final email = c.contato.trim();
      if (!emailValido(email)) return null;
      final assunto = lembrete ? 'Confirmação de presença: ${a.titulo}' : 'Convite: ${a.titulo}';
      // Uri.encodeComponent usa %20 para espaço (queryParameters usaria "+", que apareceria no e-mail).
      return Uri.parse('mailto:$email?subject=${Uri.encodeComponent(assunto)}&body=${Uri.encodeComponent(texto)}');
    }
    final fone = telefoneParaWhatsapp(c.contato);
    if (fone == null) return null;
    return Uri.parse('https://wa.me/$fone?text=${Uri.encodeComponent(texto)}');
  }

  /// Abre o WhatsApp ou o e-mail. Retorna false se não deu para abrir.
  static Future<bool> enviar(Agendamento a, Convidado c, {required bool lembrete}) async {
    final url = urlPara(a, c, lembrete: lembrete);
    if (url == null) return false;
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}