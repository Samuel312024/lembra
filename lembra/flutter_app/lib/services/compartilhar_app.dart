import 'package:share_plus/share_plus.dart';

class CompartilharApp {
  static const link = 'https://play.google.com/store/apps/details?id=com.samsolution.mylembra';

  static Future<void> compartilhar() => SharePlus.instance.share(
        ShareParams(
          subject: 'Conheça o Lembra',
          text: 'Uso o Lembra para não esquecer compromissos, tarefas e contas. Baixe aqui: $link',
        ),
      );
}