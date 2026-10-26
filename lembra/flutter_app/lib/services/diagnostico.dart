// Coloque em: lib/services/diagnostico.dart
//
// Guarda no aparelho os últimos erros do app, para o usuário poder enviar um
// relatório quando algo der errado (Ajustes > Dados e diagnóstico).
// Nada sai do aparelho sozinho.

import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Diagnostico {
  Diagnostico._();

  static const _chave = 'diagnostico_erros';
  static const _maximo = 20;

  static SharedPreferences? _prefs;

  /// Chame uma vez no main(), logo depois de abrir o SharedPreferences.
  static void iniciar(SharedPreferences prefs) {
    _prefs = prefs;

    final anterior = FlutterError.onError;
    FlutterError.onError = (detalhes) {
      registrar('Flutter', detalhes.exceptionAsString(), detalhes.stack);
      anterior?.call(detalhes); // mantém o comportamento padrão (log no console)
    };

    PlatformDispatcher.instance.onError = (erro, pilha) {
      registrar('App', erro.toString(), pilha);
      return false; // false = o Flutter continua tratando como antes
    };
  }

  /// Anota um erro (sem esperar; nunca lança exceção).
  static void registrar(String origem, String mensagem, StackTrace? pilha) {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final resumo = (pilha?.toString() ?? '').split('\n').take(6).join('\n');
      final linha = '${DateTime.now().toIso8601String()} [$origem] $mensagem\n$resumo'.trim();
      final lista = [...erros(), linha];
      final recentes = lista.length > _maximo ? lista.sublist(lista.length - _maximo) : lista;
      prefs.setString(_chave, jsonEncode(recentes));
    } catch (_) {
      // registrar erro não pode causar outro erro
    }
  }

  /// Do mais antigo para o mais novo.
  static List<String> erros() {
    final bruto = _prefs?.getString(_chave);
    if (bruto == null) return [];
    try {
      return (jsonDecode(bruto) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> limpar() async {
    await _prefs?.remove(_chave);
  }
}