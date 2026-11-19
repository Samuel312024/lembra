// Coloque em: lib/ui/convidados_sheet.dart
//
// Folha "Convidados": mostra quem aceitou, recusou ou ainda não respondeu,
// envia o convite (WhatsApp ou e-mail), cobra quem não respondeu e deixa o
// usuário registrar a resposta de cada pessoa com um toque.
//
// Com login, a reunião vai para o servidor: cada convidado recebe um link e a
// resposta aparece aqui sozinha. Sem login, segue o jeito manual de sempre.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/agendamento.dart';
import '../services/convite_service.dart';
import '../state/agendamentos_provider.dart';
import 'theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Peças visuais compartilhadas com a tela de reuniões
// ---------------------------------------------------------------------------

Widget etiquetaReuniao(String texto, Color cor, {IconData? icone, bool seta = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 13, color: cor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          if (seta) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 15, color: cor),
          ],
        ],
      ),
    );

Color corResposta(BuildContext context, RespostaConvite r) => switch (r) {
      RespostaConvite.aceito => AppColors.green,
      RespostaConvite.recusado => context.cores.perigo,
      RespostaConvite.talvez => AppColors.orange,
      RespostaConvite.pendente => context.cores.suave,
    };

IconData iconeResposta(RespostaConvite r) => switch (r) {
      RespostaConvite.aceito => Icons.check_circle_rounded,
      RespostaConvite.recusado => Icons.cancel_rounded,
      RespostaConvite.talvez => Icons.help_rounded,
      RespostaConvite.pendente => Icons.schedule_rounded,
    };

// ---------------------------------------------------------------------------
// Folha
// ---------------------------------------------------------------------------

class FolhaConvidados extends ConsumerStatefulWidget {
  const FolhaConvidados({super.key, required this.agendamentoId});

  final String agendamentoId;

  @override
  ConsumerState<FolhaConvidados> createState() => _FolhaConvidadosState();
}

class _FolhaConvidadosState extends ConsumerState<FolhaConvidados> {
  @override
  void initState() {
    super.initState();
    // Traz as respostas dadas pelos links assim que a folha abre.
    Future.microtask(() => ref.read(agendamentosProvider.notifier).atualizarRespostasDoServidor());
  }

  Widget _barra(BuildContext context, Agendamento a) {
    final partes = <(int, Color)>[
      (a.aceitos, AppColors.green),
      (a.talvez, AppColors.orange),
      (a.recusados, context.cores.perigo),
      (a.pendentes, context.cores.borda),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final p in partes)
              if (p.$1 > 0) Expanded(flex: p.$1, child: Container(color: p.$2)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final registros = ref.watch(agendamentosProvider);
    Agendamento? encontrado;
    for (final x in registros) {
      if (x.id == widget.agendamentoId) {
        encontrado = x;
        break;
      }
    }
    final a = encontrado;
    if (a == null) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Esta reunião não existe mais.', textAlign: TextAlign.center),
        ),
      );
    }

    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final hm = DateFormat.Hm('pt_BR');
    final dia = toBeginningOfSentenceCase(DateFormat("EEE, d 'de' MMM", 'pt_BR').format(a.inicio)) ?? '';

    final temGoogle = a.eventoId != null && a.convidados.any((g) => g.canal == CanalConvite.email);
    final temServidor = a.remotoId != null;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Convidados', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c.texto)),
              const SizedBox(height: 4),
              Text(
                '${a.titulo} · $dia, ${hm.format(a.inicio)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: c.suave),
              ),
              const SizedBox(height: 16),
              if (a.convidados.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nenhum convidado ainda. Toque em Editar na reunião para adicionar pessoas.',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: c.suave),
                  ),
                )
              else ...[
                _barra(context, a),
                const SizedBox(height: 8),
                Text(
                  a.resumoRespostas,
                  style: t.bodySmall?.copyWith(color: c.suave, fontWeight: FontWeight.w600),
                ),
                if (temGoogle || temServidor)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final notificador = ref.read(agendamentosProvider.notifier);
                        await notificador.sincronizarComCalendario();
                        await notificador.atualizarRespostasDoServidor();
                        messenger.showSnackBar(const SnackBar(content: Text('Respostas atualizadas.')));
                      },
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Atualizar respostas'),
                      style: TextButton.styleFrom(
                        foregroundColor: c.marca,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                for (final conv in a.convidados)
                  _TileConvidado(key: ValueKey(conv.id), agendamento: a, convidado: conv),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: ConviteService.mensagemConvite(a)));
                  messenger.showSnackBar(const SnackBar(content: Text('Texto do convite copiado.')));
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copiar texto do convite'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Uma pessoa
// ---------------------------------------------------------------------------

class _TileConvidado extends ConsumerWidget {
  const _TileConvidado({super.key, required this.agendamento, required this.convidado});

  final Agendamento agendamento;
  final Convidado convidado;

  static String _opcao(RespostaConvite r) => switch (r) {
        RespostaConvite.aceito => 'Aceitou',
        RespostaConvite.recusado => 'Recusou',
        RespostaConvite.talvez => 'Talvez',
        RespostaConvite.pendente => 'Voltar para aguardando',
      };

  Future<void> _enviar(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final notificador = ref.read(agendamentosProvider.notifier);
    final lembrete = convidado.conviteEnviadoEm != null;

    // Com login, a reunião vai para o servidor: os convidados ganham um link e a
    // resposta chega sozinha. Sem login ou sem conexão, segue o jeito manual de sempre.
    final servidor = await notificador.garantirNoServidor(agendamento.id);
    if (servidor.estado == EstadoServidor.falhou && servidor.mensagem != null) {
      messenger.showSnackBar(SnackBar(content: Text('${servidor.mensagem} Enviando do jeito manual.')));
    }

    // Depois do await, os objetos antigos ficaram velhos: pega os atuais (com o link).
    final reuniao = notificador.porId(agendamento.id) ?? agendamento;
    final fresco = notificador.convidadoAtual(agendamento.id, convidado.id) ?? convidado;

    final noServidor = servidor.ok && reuniao.remotoId != null && fresco.remotoId != null;
    if (noServidor && fresco.canal == CanalConvite.email) {
      if (servidor.criou) {
        // O servidor acabou de mandar o e-mail com o link.
        if (fresco.conviteEnviadoEm != null) {
          messenger.showSnackBar(const SnackBar(content: Text('Convite enviado por e-mail.')));
          return;
        }
      } else if (lembrete) {
        final r = await notificador.reenviarPeloServidor(agendamento.id, convidado.id);
        messenger.showSnackBar(SnackBar(content: Text(r.mensagem ?? 'Lembrete enviado por e-mail.')));
        return;
      }
    }

    // WhatsApp (com o link, se o servidor já conhece a pessoa) ou e-mail que o
    // servidor não enviou: abre o app com o texto pronto.
    final ok = await ConviteService.enviar(reuniao, fresco, lembrete: lembrete);
    if (!ok) {
      messenger.showSnackBar(SnackBar(
        content: Text(convidado.canal == CanalConvite.email
            ? 'Não consegui abrir o app de e-mail.'
            : 'Não consegui abrir o WhatsApp.'),
      ));
      return;
    }
    await notificador.marcarEnviado(agendamento.id, convidado.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final cor = corResposta(context, convidado.resposta);
    final inicial = convidado.nome.trim().isEmpty ? '?' : convidado.nome.trim()[0].toUpperCase();
    final email = convidado.canal == CanalConvite.email;
    final pendente = convidado.resposta == RespostaConvite.pendente;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: cor.withValues(alpha: 0.14),
            child: Text(inicial, style: TextStyle(color: cor, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  convidado.nome,
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: c.texto),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(email ? Icons.mail_outline_rounded : Icons.chat_outlined, size: 14, color: c.suave),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        convidado.contato,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: c.suave),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PopupMenuButton<RespostaConvite>(
                      tooltip: 'Registrar resposta',
                      onSelected: (r) => ref
                          .read(agendamentosProvider.notifier)
                          .definirResposta(agendamento.id, convidado.id, r),
                      itemBuilder: (_) => [
                        for (final r in RespostaConvite.values)
                          if (r != convidado.resposta)
                            PopupMenuItem<RespostaConvite>(
                              value: r,
                              child: Row(
                                children: [
                                  Icon(iconeResposta(r), size: 18, color: corResposta(context, r)),
                                  const SizedBox(width: 10),
                                  Text(_opcao(r)),
                                ],
                              ),
                            ),
                      ],
                      child: etiquetaReuniao(
                        convidado.statusRotulo,
                        cor,
                        icone: iconeResposta(convidado.resposta),
                        seta: true,
                      ),
                    ),
                    if (pendente)
                      TextButton.icon(
                        onPressed: () => _enviar(context, ref),
                        icon: Icon(
                          convidado.conviteEnviadoEm == null ? Icons.send_rounded : Icons.notifications_active_outlined,
                          size: 16,
                        ),
                        label: Text(convidado.conviteEnviadoEm == null ? 'Enviar convite' : 'Cobrar resposta'),
                        style: TextButton.styleFrom(
                          foregroundColor: c.marca,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_legenda(email), style: t.bodySmall?.copyWith(color: c.suave, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Explica de onde vem (ou virá) a resposta, para ninguém ficar esperando à toa.
  String _legenda(bool email) {
    if (convidado.automatica) return 'Respondeu pelo Google Agenda';
    if (convidado.resposta != RespostaConvite.pendente) {
      return convidado.remotoId != null ? 'Resposta registrada' : 'Resposta registrada por você';
    }
    if (convidado.link != null) return 'A resposta aparece aqui quando a pessoa tocar no link.';
    return email
        ? 'O Google Agenda atualiza aqui quando a pessoa responder.'
        : 'Registre a resposta quando ela chegar no WhatsApp.';
  }
}