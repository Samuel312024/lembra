// Coloque em: lib/data/api_client.dart  (substitui o arquivo atual)

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiErro implements Exception {
  ApiErro(this.status, this.codigo);
  final int status;
  final String codigo;

  @override
  String toString() => 'ApiErro($status, $codigo)';

  /// Mensagem em português para mostrar ao usuário.
  String get mensagem => switch (codigo) {
        'email_em_uso' => 'Esse e-mail já está cadastrado.',
        'credenciais_invalidas' => 'E-mail ou senha incorretos.',
        'limite_diario' => 'Limite diário de interpretações por IA atingido.',
        'dados_invalidos' => 'Dados inválidos. Confira o e-mail e use uma senha com 8+ caracteres.',
        'inicio_no_passado' => 'Para enviar convites, a reunião precisa ser no futuro.',
        'limite_diario_convites' => 'Limite diário de convites atingido.',
        'reuniao_cancelada' => 'Esta reunião já foi cancelada.',
        'reuniao_encerrada' => 'Esta reunião já aconteceu.',
        'limite_participantes' => 'Uma reunião aceita no máximo 50 convidados.',
        'participante_nao_encontrado' => 'Esse convidado não está mais na reunião.',
        _ => status == 401
            ? 'Entre na sua conta para usar os convites automáticos.'
            : 'Não foi possível falar com o servidor.',
      };
}

/// ISO 8601 com deslocamento de fuso (ex.: 2026-10-16T10:00:00-03:00).
String isoComFuso(DateTime d) {
  final off = d.timeZoneOffset;
  final sinal = off.isNegative ? '-' : '+';
  final h = off.inHours.abs().toString().padLeft(2, '0');
  final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${d.toIso8601String().split('.').first}$sinal$h:$m';
}

/// Cliente da API. A chave da IA fica só no servidor; o app nunca a vê.
/// Endereço configurável: flutter run --dart-define=API_URL=http://192.168.0.10:3000
class ApiClient {
  ApiClient({http.Client? cliente}) : _http = cliente ?? http.Client();

  static const baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');

  final http.Client _http;
  final _storage = const FlutterSecureStorage();

  Future<String?> token() => _storage.read(key: 'token');
  Future<void> guardarToken(String t) => _storage.write(key: 'token', value: t);
  Future<void> apagarToken() => _storage.delete(key: 'token');

  Future<Map<String, String>> _cabecalhos({bool auth = true}) async {
    final t = auth ? await token() : null;
    return {
      'content-type': 'application/json',
      if (t != null) 'authorization': 'Bearer $t',
    };
  }

  Map<String, dynamic> _corpo(http.Response r) {
    final texto = r.bodyBytes.isEmpty ? '{}' : utf8.decode(r.bodyBytes);
    final dados = jsonDecode(texto);
    final mapa = dados is Map<String, dynamic> ? dados : <String, dynamic>{};
    if (r.statusCode >= 400) throw ApiErro(r.statusCode, '${mapa['erro'] ?? 'erro'}');
    return mapa;
  }

  Future<Map<String, dynamic>> _post(
    String caminho,
    Map<String, Object?> corpo, {
    bool auth = true,
    Duration limite = const Duration(seconds: 15),
  }) async {
    final r = await _http
        .post(Uri.parse('$baseUrl$caminho'), headers: await _cabecalhos(auth: auth), body: jsonEncode(corpo))
        .timeout(limite);
    return _corpo(r);
  }

  Future<Map<String, dynamic>> _get(
    String caminho, {
    Duration limite = const Duration(seconds: 15),
  }) async {
    final r = await _http.get(Uri.parse('$baseUrl$caminho'), headers: await _cabecalhos()).timeout(limite);
    return _corpo(r);
  }

  Future<Map<String, dynamic>> _patch(
    String caminho,
    Map<String, Object?> corpo, {
    Duration limite = const Duration(seconds: 15),
  }) async {
    final r = await _http
        .patch(Uri.parse('$baseUrl$caminho'), headers: await _cabecalhos(), body: jsonEncode(corpo))
        .timeout(limite);
    return _corpo(r);
  }

  Future<Map<String, dynamic>> _apagar(
    String caminho, {
    Duration limite = const Duration(seconds: 15),
  }) async {
    final r = await _http.delete(Uri.parse('$baseUrl$caminho'), headers: await _cabecalhos()).timeout(limite);
    return _corpo(r);
  }

  Future<Map<String, dynamic>> registrar(String email, String senha) =>
      _post('/auth/registrar', {'email': email, 'senha': senha}, auth: false);

  Future<Map<String, dynamic>> entrar(String email, String senha) =>
      _post('/auth/entrar', {'email': email, 'senha': senha}, auth: false);

  /// Entendimento por IA (o servidor devolve JSON validado).
  Future<Map<String, dynamic>> entender(String texto, DateTime agora, int horarioPadraoMin) =>
      _post(
        '/ia/entender',
        {
          'texto': texto,
          'agora': isoComFuso(agora),
          'fuso': agora.timeZoneName,
          'horario_padrao_min': horarioPadraoMin,
        },
        limite: const Duration(seconds: 4),
      );

  Future<Map<String, dynamic>> sincronizar(int desde, List<Map<String, Object?>> itens) =>
      _post('/sync', {'desde': desde, 'itens': itens});

  // -------------------------------------------------------------------------
  // Convites (reuniões com resposta automática)
  // O envio de e-mails acontece no servidor e pode demorar, por isso o limite maior.
  // -------------------------------------------------------------------------

  /// Cria a reunião no servidor: grava os convidados, envia os e-mails e devolve
  /// o link de resposta de cada pessoa.
  Future<Map<String, dynamic>> criarConvite(Map<String, Object?> corpo) =>
      _post('/convites', corpo, limite: const Duration(seconds: 30));

  /// Reuniões dos últimos 30 dias em diante, com as respostas atuais. Vem em {"reunioes": [...]}.
  Future<Map<String, dynamic>> listarConvites() => _get('/convites');

  /// Edita título, início, local ou descrição. Mudou o horário? O servidor zera as respostas.
  Future<Map<String, dynamic>> editarConvite(String id, Map<String, Object?> corpo) =>
      _patch('/convites/$id', corpo, limite: const Duration(seconds: 30));

  /// Cancela a reunião e avisa os convidados.
  Future<Map<String, dynamic>> cancelarConvite(String id) =>
      _apagar('/convites/$id', limite: const Duration(seconds: 30));

  /// Inclui convidados numa reunião que já está no servidor. Só os novos recebem o e-mail;
  /// devolve a reunião completa, com o link de cada convidado.
  Future<Map<String, dynamic>> adicionarParticipantes(String id, Map<String, Object?> corpo) =>
      _post('/convites/$id/participantes', corpo, limite: const Duration(seconds: 30));

  /// Reenvia o convite: para um convidado ([participanteId]) ou para todos que não responderam.
  Future<Map<String, dynamic>> reenviarConvite(String id, {String? participanteId}) =>
      _post('/convites/$id/reenviar', {if (participanteId != null) 'participanteId': participanteId});

  /// Exclusão total dos dados da conta (LGPD).
  Future<void> excluirConta() async {
    final r = await _http
        .delete(Uri.parse('$baseUrl/conta'), headers: await _cabecalhos())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 400) throw ApiErro(r.statusCode, 'erro');
  }
}