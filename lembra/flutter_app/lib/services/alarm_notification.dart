// Coloque em: lib/services/alarm_notification.dart
//
// Antes de usar:
// 1) Copie o som para: android/app/src/main/res/raw/alarme.mp3
//    (nome só com letras minúsculas, números e "_"; também serve .wav ou .ogg).
// 2) Chame criarCanalAlarme(plugin) uma vez, logo depois do initialize() do plugin.
// 3) Nos seus zonedSchedule()/show(), troque o NotificationDetails atual por
//    detalhesAlarme() (o parâmetro se chama "notificationDetails" nas versões
//    novas do plugin e "details" nas antigas). Se você já tem botões nas
//    notificações (soneca, concluir), passe-os em detalhesAlarme(acoes: ...).
//
// Rode "flutter analyze": se a sua versão do plugin pedir parâmetros nomeados
// em algum construtor, o analisador aponta a linha.

import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// O som pertence ao CANAL e não pode ser trocado depois que o canal existe no
/// aparelho. Por isso o id tem sufixo de versão: para trocar o som ou outra
/// configuração do canal, crie um id novo (ex.: lembra_alarme_v3).
const String kCanalAlarmeId = 'lembra_alarme_v2';
const String kCanalAlarmeNome = 'Alarmes do Lembra';
const String kCanalAlarmeDescricao = 'Lembretes que despertam com o som do app';

/// Nome do arquivo em res/raw, sem a extensão.
const String kSomAlarme = 'alarme';

const AndroidNotificationChannel canalAlarme = AndroidNotificationChannel(
  kCanalAlarmeId,
  kCanalAlarmeNome,
  description: kCanalAlarmeDescricao,
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound(kSomAlarme),
  audioAttributesUsage: AudioAttributesUsage.alarm,
  enableVibration: true,
);

Future<void> criarCanalAlarme(FlutterLocalNotificationsPlugin plugin) async {
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(canalAlarme);
}

NotificationDetails detalhesAlarme({List<AndroidNotificationAction>? acoes}) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      kCanalAlarmeId,
      kCanalAlarmeNome,
      channelDescription: kCanalAlarmeDescricao,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound(kSomAlarme),
      // Toca no volume de ALARME, mesmo com o celular no silencioso.
      audioAttributesUsage: AudioAttributesUsage.alarm,
      // 4 = FLAG_INSISTENT: repete o som até o usuário mexer na notificação.
      additionalFlags: Int32List.fromList(<int>[4]),
      actions: acoes,
    ),
  );
}