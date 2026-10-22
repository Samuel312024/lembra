import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Alarme que está tocando agora no Android.
class AlarmeTocando {
  const AlarmeTocando({required this.itemId, required this.titulo, required this.corpo});

  final String itemId;
  final String titulo;
  final String corpo;

  static AlarmeTocando? de(Object? m) {
    if (m is! Map) return null;
    final id = m['itemId'];
    if (id is! String || id.isEmpty) return null;
    return AlarmeTocando(itemId: id, titulo: '${m['titulo'] ?? ''}', corpo: '${m['corpo'] ?? ''}');
  }
}

/// Ponte com o serviço nativo (Kotlin) que toca o alarme crítico: som de despertador
/// em loop, tela acesa e app aberto por cima de tudo, em qualquer situação.
/// Só existe no Android; no iOS todos os métodos são inertes.
class AlarmeNativo {
  AlarmeNativo._();
  static final instance = AlarmeNativo._();

  static const _canal = MethodChannel('lembra/alarme');

  bool get disponivel => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// O app já está aberto e o alarme acaba de tocar.
  void Function(AlarmeTocando alarme)? aoTocar;

  void iniciar() {
    if (!disponivel) return;
    _canal.setMethodCallHandler((call) async {
      if (call.method == 'tocando') {
        final a = AlarmeTocando.de(call.arguments);
        if (a != null) aoTocar?.call(a);
      }
    });
  }

  Future<T?> _chamar<T>(String metodo, [Map<String, Object?>? args]) async {
    if (!disponivel) return null;
    try {
      return await _canal.invokeMethod<T>(metodo, args);
    } on PlatformException catch (e) {
      debugPrint('AlarmeNativo.$metodo falhou: ${e.message}');
    } on MissingPluginException {
      debugPrint('AlarmeNativo.$metodo: código nativo não instalado (veja android_nativo/).');
    }
    return null;
  }

  /// [freq]: null (único) | 'DAILY' | 'WEEKLY' | 'MONTHLY'. [dia]: 1 = segunda ... 7 = domingo.
  Future<void> agendar({
    required String chave,
    required String itemId,
    required String titulo,
    required String corpo,
    required DateTime quando,
    String? freq,
    int dia = 0,
    int diaMes = 0,
    int hora = 0,
    int minuto = 0,
  }) =>
      _chamar<bool>('agendar', {
        'chave': chave,
        'itemId': itemId,
        'titulo': titulo,
        'corpo': corpo,
        'quando': quando.millisecondsSinceEpoch,
        'freq': freq,
        'dia': dia,
        'diaMes': diaMes,
        'hora': hora,
        'minuto': minuto,
      });

  Future<void> cancelarItem(String itemId) => _chamar<bool>('cancelarItem', {'itemId': itemId});

  Future<void> cancelarTudo() => _chamar<bool>('cancelarTudo');

  /// Para o som, a vibração e solta a tela.
  Future<void> parar() => _chamar<bool>('parar');

  Future<AlarmeTocando?> atual() async => AlarmeTocando.de(await _chamar<Object>('alarmeAtual'));

  Future<bool> temSobreposicao() async => (await _chamar<bool>('temSobreposicao')) ?? true;

  Future<void> pedirSobreposicao() => _chamar<bool>('pedirSobreposicao');
}