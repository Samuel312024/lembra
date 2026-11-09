// Coloque em: lib/state/renda_provider.dart
//
// Guarda o perfil de renda (CLT/PJ) neste aparelho.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/renda.dart';

class RendaNotifier extends AsyncNotifier<PerfilRenda?> {
  static const _chave = 'perfil_renda_v1';

  @override
  Future<PerfilRenda?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_chave);
    if (texto == null) return null;
    try {
      return PerfilRenda.fromJson(jsonDecode(texto) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> salvar(PerfilRenda perfil) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, jsonEncode(perfil.toJson()));
    state = AsyncData(perfil);
  }

  Future<void> limpar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chave);
    state = const AsyncData(null);
  }
}

final rendaProvider = AsyncNotifierProvider<RendaNotifier, PerfilRenda?>(RendaNotifier.new);