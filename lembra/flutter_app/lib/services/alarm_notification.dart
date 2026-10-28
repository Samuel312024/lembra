// Coloque em: lib/services/alarm_notification.dart
//
// Sons do alarme crítico (Android). O usuário escolhe em Ajustes > Som do alarme:
//  - sons do próprio celular (alarme, toque ou notificação padrão do aparelho);
//  - sons do Lembra, que são arquivos em android/app/src/main/res/raw/
//    (nomes só com letras minúsculas, números e "_").
//
// No Android, o som pertence ao CANAL de notificação e não muda depois que o
// canal existe. Por isso cada som tem o seu próprio canal (id com o nome do som
// e um sufixo de versão); trocar de som cria o canal novo e apaga os outros.
// Para mudar algo no canal de um som (ex.: trocar o arquivo ou o tipo de áudio),
// suba o sufixo de versão (kCanalAlarmeVersao). Recriar um canal apagado com o
// MESMO id não adianta: o Android restaura as configurações antigas dele.

import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const String kCanalAlarmePrefixo = 'lembra_alarme_v2';
// v4: canais criados antes do audioAttributesUsage.alarm ficavam presos ao
// áudio de notificação (que o modo vibrar silencia). Novo id = canal novo.
const String kCanalAlarmeVersao = 'v4';
const String kCanalAlarmeDescricao = 'Lembretes críticos que despertam com som';

class SomAlarme {
  const SomAlarme({
    required this.id,
    required this.rotulo,
    required this.descricao,
    this.recurso,
    this.uri,
  });

  final String id;
  final String rotulo;
  final String descricao;

  /// Arquivo em res/raw, sem a extensão (som do Lembra).
  final String? recurso;

  /// Endereço de um som do próprio celular.
  final String? uri;

  bool get doCelular => uri != null;

  AndroidNotificationSound get som => recurso != null
      ? RawResourceAndroidNotificationSound(recurso)
      : UriAndroidNotificationSound(uri!);
}

/// O primeiro da lista é o padrão: o alarme do celular sempre existe, então
/// o usuário nunca fica sem som, mesmo que algum arquivo do app falte.
const sonsAlarme = <SomAlarme>[
  SomAlarme(
    id: 'celular',
    rotulo: 'Alarme do celular',
    descricao: 'O som de alarme padrão do seu aparelho',
    uri: 'content://settings/system/alarm_alert',
  ),
  SomAlarme(
    id: 'toque',
    rotulo: 'Toque do celular',
    descricao: 'O toque de chamada padrão do aparelho',
    uri: 'content://settings/system/ringtone',
  ),
  SomAlarme(
    id: 'notificacao',
    rotulo: 'Notificação do celular',
    descricao: 'O som de notificação padrão do aparelho',
    uri: 'content://settings/system/notification_sound',
  ),
  SomAlarme(
    id: 'classico',
    rotulo: 'Despertador clássico',
    descricao: 'Bips rápidos e repetidos',
    recurso: 'alarme_classico',
  ),
  SomAlarme(
    id: 'suave',
    rotulo: 'Suave',
    descricao: 'Notas que sobem devagar, bom para acordar',
    recurso: 'alarme_suave',
  ),
  SomAlarme(
    id: 'sino',
    rotulo: 'Sinos',
    descricao: 'Toque de sino',
    recurso: 'alarme_sino',
  ),
  SomAlarme(
    id: 'sirene',
    rotulo: 'Sirene',
    descricao: 'Forte, difícil de ignorar',
    recurso: 'alarme_sirene',
  ),
  SomAlarme(
    id: 'digital',
    rotulo: 'Digital',
    descricao: 'Bips agudos em sequência',
    recurso: 'alarme_digital',
  ),
];

/// Acha o som pelo id gravado; id desconhecido volta ao padrão.
SomAlarme somAlarmePorId(String? id) =>
    sonsAlarme.firstWhere((s) => s.id == id, orElse: () => sonsAlarme.first);

String canalAlarmeId(SomAlarme s) => '$kCanalAlarmePrefixo${s.id}_$kCanalAlarmeVersao';

AndroidNotificationChannel canalAlarme(SomAlarme s) => AndroidNotificationChannel(
      canalAlarmeId(s),
      'Alarme: ${s.rotulo}',
      description: kCanalAlarmeDescricao,
      importance: Importance.max,
      playSound: true,
      sound: s.som,
      // Toca no volume de ALARME, mesmo com o celular no modo vibrar/silencioso.
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
    );

/// Cria o canal de TODOS os sons (cada lembrete pode usar um diferente) e
/// apaga canais de versões antigas ou de sons que não existem mais.
/// Chame uma vez na inicialização do app, antes de qualquer alarme.
Future<void> prepararCanalAlarme(FlutterLocalNotificationsPlugin plugin, [SomAlarme? _]) async {
  final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return;

  await android.deleteNotificationChannel('lembretes_critico');

  final validos = sonsAlarme.map(canalAlarmeId).toSet();
  final existentes = await android.getNotificationChannels() ?? const <AndroidNotificationChannel>[];
  for (final c in existentes) {
    if (c.id.startsWith(kCanalAlarmePrefixo) && !validos.contains(c.id)) {
      await android.deleteNotificationChannel(c.id);
    }
  }

  for (final s in sonsAlarme) {
    await android.createNotificationChannel(canalAlarme(s));
  }
}

/// Detalhes (Android) da notificação do alarme crítico.
/// [insistente] = false gera a versão curta usada no botão "Testar som".
AndroidNotificationDetails detalhesAndroidAlarme(
  SomAlarme som, {
  List<AndroidNotificationAction>? acoes,
  bool insistente = true,
}) {
  return AndroidNotificationDetails(
    canalAlarmeId(som),
    'Alarme: ${som.rotulo}',
    channelDescription: kCanalAlarmeDescricao,
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: insistente,
    playSound: true,
    sound: som.som,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    visibility: NotificationVisibility.public,
    ongoing: insistente,
    autoCancel: !insistente,
    timeoutAfter: insistente ? null : 8000,
    // 4 = FLAG_INSISTENT: repete o som até o usuário mexer na notificação.
    additionalFlags: insistente ? Int32List.fromList(<int>[4]) : null,
    actions: insistente ? acoes : null,
  );
}

/// Dispara o alarme agora, com o som escolhido pelo usuário.
/// Pressupõe que prepararCanalAlarme() já rodou na inicialização do app.
///
/// [somId] é o id gravado nos Ajustes (ex.: 'celular', 'sirene'); nulo ou
/// desconhecido cai no alarme do celular.
/// [insistente] = false toca a versão curta (8 s, sem tela cheia), ideal para
/// o botão "Testar som".
Future<void> despertar(
  FlutterLocalNotificationsPlugin plugin, {
  required int id,
  required String titulo,
  String? corpo,
  String? somId,
  String? payload,
  List<AndroidNotificationAction>? acoes,
  bool insistente = true,
}) async {
  final som = somAlarmePorId(somId);
  await plugin.show(
    id,
    titulo,
    corpo,
    NotificationDetails(
      android: detalhesAndroidAlarme(som, acoes: acoes, insistente: insistente),
    ),
    payload: payload,
  );
}