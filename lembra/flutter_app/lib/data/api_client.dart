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
        _ => 'Não foi possível falar com o servidor.',
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

  /// Exclusão total dos dados da conta (LGPD).
  Future<void> excluirConta() async {
    final r = await _http
        .delete(Uri.parse('$baseUrl/conta'), headers: await _cabecalhos())
        .timeout(const Duration(seconds: 15));
    if (r.statusCode >= 400) throw ApiErro(r.statusCode, 'erro');
  }
}
