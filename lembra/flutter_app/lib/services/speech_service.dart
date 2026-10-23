import 'package:speech_to_text/speech_to_text.dart';

/// Reconhecimento de fala nativo do aparelho (baixa latência e sem custo).
class SpeechService {
  final _stt = SpeechToText();
  bool _pronto = false;
  String _ultimo = '';
  bool _entregue = false;
  void Function(String)? _aoFinal;
  void Function()? _aoVazio;

  Future<bool> iniciar() async {
    if (_pronto) return true;
    _pronto = await _stt.initialize(
      onError: (e) => _entregar(),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') _entregar();
      },
    );
    return _pronto;
  }

  /// Começa a ouvir em pt-BR. [aoParcial] recebe a transcrição ao vivo;
  /// [aoFinal] o texto final; [aoVazio] é chamado se nada foi entendido.
  /// Retorna false se o reconhecimento não está disponível (sem permissão, por exemplo).
  Future<bool> ouvir({
    required void Function(String) aoParcial,
    required void Function(String) aoFinal,
    void Function()? aoVazio,
  }) async {
    if (!await iniciar()) return false;
    _ultimo = '';
    _entregue = false;
    _aoFinal = aoFinal;
    _aoVazio = aoVazio;
    await _stt.listen(
      onResult: (r) {
        _ultimo = r.recognizedWords;
        if (r.finalResult) {
          _entregar();
        } else {
          aoParcial(_ultimo);
        }
      },
      listenOptions: SpeechListenOptions(
      localeId: 'pt_BR',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
    return true;
  }

  void _entregar() {
    if (_entregue) return;
    _entregue = true;
    if (_ultimo.trim().isEmpty) {
      _aoVazio?.call();
    } else {
      _aoFinal?.call(_ultimo.trim());
    }
  }

  Future<void> parar() => _stt.stop();

  Future<void> cancelar() async {
    _entregue = true; // descarta qualquer resultado pendente
    await _stt.cancel();
  }
}
