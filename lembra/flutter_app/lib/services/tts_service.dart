import 'package:flutter_tts/flutter_tts.dart';

/// Leitura em voz alta (briefing do dia, respostas a comandos).
class TtsService {
  final _tts = FlutterTts();
  bool _configurado = false;

  Future<void> falar(String texto) async {
    if (!_configurado) {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.5);
      _configurado = true;
    }
    await _tts.stop();
    await _tts.speak(texto);
  }

  Future<void> parar() => _tts.stop();
}
