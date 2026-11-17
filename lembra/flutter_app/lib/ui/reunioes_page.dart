// Coloque em: lib/ui/reunioes_page.dart  (substitui o arquivo atual)
//
// Aba "Reuniões":
//  - resumo no topo: próxima reunião com contagem regressiva, reuniões de hoje e respostas pendentes;
//  - abas "Próximas" e "Histórico". Reunião agendada pelo Lembra fica salva no
//    histórico e NUNCA some sozinha: só sai quando o usuário exclui;
//  - cada reunião criada no Lembra tem menu para editar, ver convidados e excluir (com "Desfazer");
//  - respostas dos convidados (aceitou / recusou / talvez / aguardando) no próprio cartão.
//
// Reuniões que vêm só do calendário do celular continuam aparecendo como antes (somente leitura).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/agendamento.dart';
import '../domain/reuniao.dart';
import '../services/calendario_service.dart';
import '../services/evento_calendario.dart';
import '../state/agendamentos_provider.dart';
import 'convidados_sheet.dart';
import 'reuniao_form_sheet.dart';
import 'theme/app_theme.dart';
import 'widgets/ui_kit.dart';

// ---------------------------------------------------------------------------
// Estado
// ---------------------------------------------------------------------------

final calendarioServiceProvider = Provider<CalendarioService>((ref) => CalendarioService());

/// Reuniões de hoje até daqui a 30 dias. `null` = o app ainda não tem
/// permissão para ler o calendário do aparelho.
final reunioesProvider = FutureProvider.autoDispose<List<Reuniao>?>((ref) async {
  final svc = ref.watch(calendarioServiceProvider);
  if (!await svc.temPermissao()) return null;
  final agora = DateTime.now();
  return svc.listarReunioes(aPartirDe: DateTime(agora.year, agora.month, agora.day), dias: 30);
});

// ---------------------------------------------------------------------------
// Utilitários
// ---------------------------------------------------------------------------

bool _mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _tituloDia(DateTime dia, DateTime agora) {
  final diff = DateTime.utc(dia.year, dia.month, dia.day)
      .difference(DateTime.utc(agora.year, agora.month, agora.day))
      .inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Amanhã';
  if (diff == -1) return 'Ontem';
  return toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(dia)) ?? '';
}

String _duracao(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  if (m % 60 == 0) return '${m ~/ 60} h';
  return '${m ~/ 60} h ${m % 60} min';
}

String _contagem(DateTime inicio, DateTime fim, DateTime agora) {
  final hm = DateFormat.Hm('pt_BR');
  if (!agora.isBefore(inicio)) return 'Termina às ${hm.format(fim)}';
  final min = inicio.difference(agora).inMinutes;
  if (min < 1) return 'Começa agora';
  if (min < 60) return 'Começa em $min min';
  if (_mesmoDia(inicio, agora)) {
    final h = min ~/ 60;
    final m = min % 60;
    return 'Hoje às ${hm.format(inicio)} · em $h h${m > 0 ? ' $m min' : ''}';
  }
  return '${_tituloDia(inicio, agora)} às ${hm.format(inicio)}';
}

Widget _info(BuildContext context, IconData icone, String texto) {
  final c = context.cores;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icone, size: 16, color: c.suave),
      const SizedBox(width: 6),
      Flexible(child: Text(texto, style: TextStyle(color: c.suave, fontSize: 13))),
    ],
  );
}

Future<void> _abrirLink(BuildContext context, Uri url) async {
  var abriu = false;
  try {
    abriu = await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    abriu = false;
  }
  if (!abriu && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Não consegui abrir o link da reunião.')));
  }
}

Future<void> _copiarLink(BuildContext context, Uri url) async {
  await Clipboard.setData(ClipboardData(text: url.toString()));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copiado.')));
  }
}

// ---------------------------------------------------------------------------
// Uma reunião para exibir (vem do calendário, do histórico do Lembra ou dos dois)
// ---------------------------------------------------------------------------

class _ReuniaoView {
  const _ReuniaoView({
    required this.chave,
    required this.titulo,
    required this.inicio,
    required this.fim,
    required this.diaInteiro,
    required this.local,
    required this.link,
    required this.calendarioNome,
    required this.numParticipantes,
    this.agendamento,
  });

  final String chave;
  final String titulo;
  final DateTime inicio;
  final DateTime fim;
  final bool diaInteiro;
  final String local;
  final ({Uri url, String plataforma})? link;
  final String calendarioNome;
  final int numParticipantes;

  /// Registro do histórico do Lembra. null = evento que veio só do calendário.
  final Agendamento? agendamento;

  bool encerrada(DateTime agora) => agora.isAfter(fim);

  bool emAndamento(DateTime agora) => !agora.isBefore(inicio) && agora.isBefore(fim);

  /// O botão "Entrar" libera 10 minutos antes do início.
  bool podeEntrar(DateTime agora) =>
      link != null && !agora.isBefore(inicio.subtract(const Duration(minutes: 10))) && agora.isBefore(fim);

  factory _ReuniaoView.deCalendario(Reuniao r) {
    final l = r.link;
    return _ReuniaoView(
      chave: 'cal-${r.id}',
      titulo: r.titulo,
      inicio: r.inicio,
      fim: r.fim,
      diaInteiro: r.diaInteiro,
      local: r.local?.trim() ?? '',
      link: l == null ? null : (url: l.url, plataforma: l.plataforma.nome),
      calendarioNome: r.calendarioNome,
      numParticipantes: r.participantes.length,
    );
  }

  /// Quando o evento ainda existe no calendário, título e horário vêm de lá
  /// (o usuário pode ter mudado no app de calendário); os convidados e as
  /// respostas vêm sempre do registro do Lembra.
  factory _ReuniaoView.deAgendamento(Agendamento a, Reuniao? r) {
    final doTexto = detectarLink(a.linkOuLocal);
    final rl = r?.link;
    final ({Uri url, String plataforma})? link =
        doTexto ?? (rl == null ? null : (url: rl.url, plataforma: rl.plataforma.nome));
    final texto = a.linkOuLocal?.trim() ?? '';
    final local = doTexto != null ? '' : (texto.isNotEmpty ? texto : (r?.local?.trim() ?? ''));
    return _ReuniaoView(
      chave: 'ag-${a.id}',
      titulo: r?.titulo ?? a.titulo,
      inicio: r?.inicio ?? a.inicio,
      fim: r?.fim ?? a.fim,
      diaInteiro: r?.diaInteiro ?? false,
      local: local,
      link: link,
      calendarioNome: a.calendarioNome.isNotEmpty ? a.calendarioNome : (r?.calendarioNome ?? ''),
      numParticipantes: a.convidados.length,
      agendamento: a,
    );
  }
}

enum _Aba { proximas, historico }

// ---------------------------------------------------------------------------
// Aba "Reuniões"
// ---------------------------------------------------------------------------

class ReunioesPage extends ConsumerStatefulWidget {
  const ReunioesPage({super.key});

  @override
  ConsumerState<ReunioesPage> createState() => _ReunioesPageState();
}

class _ReunioesPageState extends ConsumerState<ReunioesPage> with WidgetsBindingObserver {
  Timer? _relogio;
  _Aba _aba = _Aba.proximas;

  /// Eventos do calendário escondidos enquanto a exclusão ainda pode ser desfeita.
  final _eventosOcultos = <String>{};

  int _ticks = 0;

  void _sincronizarRespostas() => unawaited(ref.read(agendamentosProvider.notifier).sincronizarComCalendario());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Atualiza a tela a cada 30 s: contagem regressiva e botão "Entrar" na hora certa.
    // A cada 2 min também confere no calendário quem respondeu ao convite do Google Agenda.
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      _ticks++;
      if (_ticks % 4 == 0) _sincronizarRespostas();
    });
    // Sempre que o calendário termina de carregar (abrir a aba, voltar para o app,
    // puxar para atualizar), lê as respostas dos convidados.
    ref.listenManual<AsyncValue<List<Reuniao>?>>(reunioesProvider, (_, next) {
      if (next.hasValue && !next.isLoading) _sincronizarRespostas();
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Ao voltar para o app, relê o calendário (o usuário pode ter mudado algo lá).
    if (estado == AppLifecycleState.resumed) ref.invalidate(reunioesProvider);
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _conectar() async {
    final ok = await ref.read(calendarioServiceProvider).pedirPermissao();
    if (!mounted) return;
    if (!ok) {
      _aviso('Permissão negada. Ative o acesso ao calendário nas configurações do app.');
    }
    ref.invalidate(reunioesProvider);
  }

  // -------------------------------------------------------------------------
  // Dados
  // -------------------------------------------------------------------------

  List<_ReuniaoView> _montar(List<Reuniao> calendario, List<Agendamento> registros) {
    final porEvento = <String, Reuniao>{for (final r in calendario) '${r.id}': r};
    final usados = <String>{};
    final views = <_ReuniaoView>[];

    for (final a in registros) {
      final id = a.eventoId;
      final r = id == null ? null : porEvento[id];
      if (id != null && r != null) usados.add(id);
      views.add(_ReuniaoView.deAgendamento(a, r));
    }
    for (final r in calendario) {
      final id = '${r.id}';
      if (usados.contains(id) || _eventosOcultos.contains(id)) continue;
      views.add(_ReuniaoView.deCalendario(r));
    }
    return views;
  }

  /// Horários ocupados, para o aviso de conflito do formulário.
  List<Intervalo> _ocupados({String? exceto}) {
    final cal = ref.read(reunioesProvider).valueOrNull ?? const <Reuniao>[];
    final agora = DateTime.now();
    return [
      for (final v in _montar(cal, ref.read(agendamentosProvider)))
        if (v.chave != exceto && !v.diaInteiro && v.fim.isAfter(agora))
          Intervalo(titulo: v.titulo, inicio: v.inicio, fim: v.fim),
    ];
  }

  // -------------------------------------------------------------------------
  // Ações
  // -------------------------------------------------------------------------

  Future<void> _agendar() async {
    final svc = ref.read(calendarioServiceProvider);
    if (!await svc.pedirPermissao()) {
      if (mounted) _aviso('Permita o acesso ao calendário para agendar reuniões.');
      return;
    }
    final calendarios = await svc.listarCalendariosEditaveis();
    if (!mounted) return;
    if (calendarios.isEmpty) {
      _aviso('Nenhum calendário editável encontrado. Adicione uma conta Google ou Outlook ao celular.');
      return;
    }
    final res = await showModalBottomSheet<ResultadoReuniao>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.cores.fundo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => FolhaReuniao(
        servico: svc,
        calendarios: calendarios,
        ocupados: _ocupados(),
        sugestoes: contatosRecentes(ref.read(agendamentosProvider)),
      ),
    );
    if (res == null || !mounted) return;
    ref.invalidate(reunioesProvider);

    final a = res.agendamento;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Reunião agendada em ${a.calendarioNome}.'),
      action: a.convidados.isEmpty
          ? null
          : SnackBarAction(label: 'Enviar convites', onPressed: () => _abrirConvidados(a.id)),
    ));
  }

  Future<void> _editar(_ReuniaoView v) async {
    final a = v.agendamento;
    if (a == null) return;
    // Edita a versão que está na tela (título e horário vindos do calendário, se mudaram lá).
    final base = a.copiar()
      ..titulo = v.titulo
      ..inicio = v.inicio
      ..fim = v.fim;
    final res = await showModalBottomSheet<ResultadoReuniao>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.cores.fundo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => FolhaReuniao(
        servico: ref.read(calendarioServiceProvider),
        existente: base,
        ocupados: _ocupados(exceto: v.chave),
        sugestoes: contatosRecentes(ref.read(agendamentosProvider)),
      ),
    );
    if (res == null || !mounted) return;
    ref.invalidate(reunioesProvider);
    _aviso(res.calendarioOk
        ? 'Reunião atualizada.'
        : 'Alterações salvas no Lembra, mas o evento no calendário não foi atualizado.');
  }

  Future<void> _excluir(_ReuniaoView v) async {
    final a = v.agendamento;
    if (a == null) return;
    final temEventoNoCalendario = a.eventoId != null && a.calendarioId != null;
    var removerDoCalendario = temEventoNoCalendario;
    final hm = DateFormat.Hm('pt_BR');

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Excluir reunião?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${_tituloDia(v.inicio, DateTime.now())}, ${hm.format(v.inicio)}'),
              if (temEventoNoCalendario) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: removerDoCalendario,
                  onChanged: (x) => setLocal(() => removerDoCalendario = x ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Remover também do calendário do celular'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Manter')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: context.cores.perigo),
              child: const Text('Excluir'),
            ),
          ],
        ),
      ),
    );
    if (confirmou != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(agendamentosProvider.notifier);
    // Só apaga do calendário depois que a janela do "Desfazer" fechar.
    final eventoId = removerDoCalendario ? a.eventoId : null;
    final calendarioId = removerDoCalendario ? a.calendarioId : null;

    await notifier.excluir(a.id);
    if (eventoId != null && calendarioId != null && mounted) {
      setState(() => _eventosOcultos.add(eventoId));
    }

    final aviso = messenger.showSnackBar(SnackBar(
      content: Text('“${a.titulo}” excluída.'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () {
          notifier.restaurar(a);
          if (eventoId != null && mounted) setState(() => _eventosOcultos.remove(eventoId));
        },
      ),
    ));

    final motivo = await aviso.closed;
    if (motivo == SnackBarClosedReason.action) return;
    if (eventoId != null && calendarioId != null) {
      await EventoCalendario().excluir(calendarioId, eventoId);
      if (!mounted) return;
      setState(() => _eventosOcultos.remove(eventoId));
      ref.invalidate(reunioesProvider);
    }
  }

  void _abrirConvidados(String agendamentoId) {
    _sincronizarRespostas(); // abre já com as respostas mais recentes
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.cores.fundo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => FolhaConvidados(agendamentoId: agendamentoId),
    );
  }

  // -------------------------------------------------------------------------
  // Visual
  // -------------------------------------------------------------------------

  Widget _mensagem({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String texto,
    required String botao,
    required VoidCallback aoTocar,
  }) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon: icone, color: cor, size: 72),
            const SizedBox(height: 16),
            Text(titulo, textAlign: TextAlign.center, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(texto, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.suave)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: aoTocar,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                shape: const StadiumBorder(),
                minimumSize: const Size(200, 48),
              ),
              child: Text(botao),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoAgendar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: FilledButton.icon(
          onPressed: _agendar,
          icon: const Icon(Icons.event_available_rounded),
          label: const Text('Agendar reunião'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.brand,
            shape: const StadiumBorder(),
          ),
        ),
      );

  Widget _chipAba(String rotulo, int n, _Aba aba) {
    final c = context.cores;
    final sel = _aba == aba;
    return ChoiceChip(
      label: Text(n > 0 ? '$rotulo · $n' : rotulo),
      selected: sel,
      showCheckmark: false,
      onSelected: (_) => setState(() => _aba = aba),
      shape: const StadiumBorder(),
      backgroundColor: c.cartao,
      selectedColor: c.marca.withValues(alpha: 0.18),
      side: BorderSide(color: sel ? c.marca : c.borda),
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: sel ? c.marca : c.texto),
    );
  }

  Widget _abas(int proximas, int historico) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            _chipAba('Próximas', proximas, _Aba.proximas),
            const SizedBox(width: 8),
            _chipAba('Histórico', historico, _Aba.historico),
          ],
        ),
      );

  /// Cartão do topo: o que vem a seguir e o que precisa de atenção.
  Widget _resumo(List<_ReuniaoView> proximas, DateTime agora) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final prox = proximas.first;
    final andamento = prox.emAndamento(agora);
    final hoje = proximas.where((v) => _mesmoDia(v.inicio, agora)).length;

    var pendentes = 0;
    var porEnviar = 0;
    for (final v in proximas) {
      final a = v.agendamento;
      if (a == null) continue;
      pendentes += a.pendentes;
      porEnviar += a.semConvite;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.marca.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.marca.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              andamento ? 'EM ANDAMENTO' : 'PRÓXIMA REUNIÃO',
              style: t.labelSmall?.copyWith(color: c.marca, fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
            const SizedBox(height: 6),
            Text(
              prox.titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.texto),
            ),
            const SizedBox(height: 2),
            Text(
              prox.diaInteiro ? 'Dia inteiro' : _contagem(prox.inicio, prox.fim, agora),
              style: t.bodyMedium?.copyWith(color: c.suave),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                etiquetaReuniao('$hoje hoje', c.marca, icone: Icons.today_rounded),
                if (pendentes > 0)
                  etiquetaReuniao(
                    '$pendentes ${pendentes == 1 ? 'resposta pendente' : 'respostas pendentes'}',
                    AppColors.orange,
                    icone: Icons.hourglass_top_rounded,
                  ),
                if (porEnviar > 0)
                  etiquetaReuniao(
                    '$porEnviar ${porEnviar == 1 ? 'convite por enviar' : 'convites por enviar'}',
                    c.suave,
                    icone: Icons.send_rounded,
                  ),
              ],
            ),
            if (prox.podeEntrar(agora)) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _abrirLink(context, prox.link!.url),
                icon: const Icon(Icons.login_rounded),
                label: Text('Entrar · ${prox.link!.plataforma}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: AppColors.brand,
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vazio() {
    final historico = _aba == _Aba.historico;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
      child: Text(
        historico
            ? 'O histórico guarda as reuniões que você agenda pelo Lembra. Elas só saem daqui se você excluir.'
            : 'Nenhuma reunião nos próximos 30 dias.\nPuxe para baixo para atualizar.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.cores.suave),
      ),
    );
  }

  Widget _lista(List<Reuniao> calendario, List<Agendamento> registros) {
    final agora = DateTime.now();
    final todas = _montar(calendario, registros);
    final proximas = todas.where((v) => !v.encerrada(agora)).toList()..sort((a, b) => a.inicio.compareTo(b.inicio));
    final historico = todas.where((v) => v.encerrada(agora)).toList()..sort((a, b) => b.inicio.compareTo(a.inicio));
    final exibidas = _aba == _Aba.proximas ? proximas : historico;

    final porDia = <DateTime, List<_ReuniaoView>>{};
    for (final v in exibidas) {
      final dia = DateTime(v.inicio.year, v.inicio.month, v.inicio.day);
      (porDia[dia] ??= []).add(v);
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(reunioesProvider);
        await ref.read(reunioesProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 200),
        children: [
          if (_aba == _Aba.proximas && proximas.isNotEmpty) _resumo(proximas, agora),
          _botaoAgendar(),
          _abas(proximas.length, historico.length),
          if (exibidas.isEmpty) _vazio(),
          for (final e in porDia.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: SectionHeader(_tituloDia(e.key, agora), count: e.value.length),
            ),
            for (final v in e.value)
              _CartaoReuniao(
                key: ValueKey(v.chave),
                v: v,
                agora: agora,
                onEditar: () => _editar(v),
                onExcluir: () => _excluir(v),
                onConvidados: () {
                  final a = v.agendamento;
                  if (a != null) _abrirConvidados(a.id);
                },
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(reunioesProvider);
    final registros = ref.watch(agendamentosProvider);
    return estado.when(
      // Mantém a lista na tela enquanto recarrega (evita o "pisca" ao voltar para o app).
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _mensagem(
        icone: Icons.error_outline_rounded,
        cor: AppColors.red,
        titulo: 'Não consegui ler o calendário',
        texto: 'Verifique se há uma conta de calendário no celular e tente de novo.',
        botao: 'Tentar de novo',
        aoTocar: () => ref.invalidate(reunioesProvider),
      ),
      data: (lista) {
        if (lista == null) {
          return _mensagem(
            icone: Icons.event_note_rounded,
            cor: AppColors.brand,
            titulo: 'Conecte seu calendário',
            texto: 'O Lembra mostra as reuniões do calendário do celular (Google, Outlook, Teams, '
                'Meet...) e permite agendar novas. Nada é alterado sem a sua confirmação.',
            botao: 'Conectar calendário',
            aoTocar: _conectar,
          );
        }
        return _lista(lista, registros);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cartão de uma reunião
// ---------------------------------------------------------------------------

class _CartaoReuniao extends StatelessWidget {
  const _CartaoReuniao({
    super.key,
    required this.v,
    required this.agora,
    required this.onEditar,
    required this.onExcluir,
    required this.onConvidados,
  });

  final _ReuniaoView v;
  final DateTime agora;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final VoidCallback onConvidados;

  /// Cor da faixa lateral: resume o estado da reunião de relance.
  Color _acento(BuildContext context) {
    final c = context.cores;
    if (v.encerrada(agora)) return c.suave;
    if (v.emAndamento(agora)) return c.marca;
    final a = v.agendamento;
    if (a == null || a.convidados.isEmpty) return c.marca;
    if (a.recusados > 0) return c.perigo;
    if (a.todosAceitaram) return AppColors.green;
    return AppColors.orange;
  }

  Widget _itemMenu(IconData icone, String texto, Color cor) => Row(
        children: [
          Icon(icone, size: 20, color: cor),
          const SizedBox(width: 12),
          Text(texto, style: TextStyle(color: cor)),
        ],
      );

  Widget _menu(BuildContext context) {
    final c = context.cores;
    return PopupMenuButton<String>(
      tooltip: 'Opções da reunião',
      icon: Icon(Icons.more_vert_rounded, color: c.suave),
      padding: EdgeInsets.zero,
      onSelected: (s) {
        switch (s) {
          case 'editar':
            onEditar();
          case 'convidados':
            onConvidados();
          case 'excluir':
            onExcluir();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'editar', child: _itemMenu(Icons.edit_outlined, 'Editar', c.texto)),
        PopupMenuItem(value: 'convidados', child: _itemMenu(Icons.group_outlined, 'Convidados e respostas', c.texto)),
        PopupMenuItem(value: 'excluir', child: _itemMenu(Icons.delete_outline_rounded, 'Excluir', c.perigo)),
      ],
    );
  }

  Widget _blocoConvidados(BuildContext context, Agendamento a, Color acento) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final n = a.convidados.length;
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 6),
      child: InkWell(
        onTap: onConvidados,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: acento.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.group_outlined, size: 20, color: acento),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n == 1 ? '1 convidado' : '$n convidados',
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: c.texto),
                    ),
                    Text(a.resumoRespostas, style: t.bodySmall?.copyWith(color: c.suave)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.suave),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final hm = DateFormat.Hm('pt_BR');
    final encerrada = v.encerrada(agora);
    final andamento = v.emAndamento(agora);
    final a = v.agendamento;
    final acento = _acento(context);
    final horario = v.diaInteiro ? 'Dia inteiro' : '${hm.format(v.inicio)} – ${hm.format(v.fim)}';

    return Opacity(
      opacity: encerrada ? 0.8 : 1,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.cartao,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: andamento ? c.marca : c.borda, width: andamento ? 1.5 : 1),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: acento),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, a != null ? 6 : 14, a != null ? 2 : 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule_rounded, size: 16, color: c.suave),
                                    const SizedBox(width: 6),
                                    Text(horario, style: AppText.mono(size: 14, color: c.texto)),
                                  ],
                                ),
                                if (!v.diaInteiro)
                                  Text(_duracao(v.fim.difference(v.inicio)),
                                      style: t.labelMedium?.copyWith(color: c.suave)),
                                if (andamento) etiquetaReuniao('Em andamento', c.marca),
                                if (encerrada) etiquetaReuniao('Encerrada', c.suave),
                              ],
                            ),
                          ),
                          if (a != null) _menu(context),
                        ],
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: a != null ? 2 : 8, right: a != null ? 12 : 0),
                        child: Text(
                          v.titulo,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.texto),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          if (v.link != null)
                            _info(context, Icons.videocam_rounded, v.link!.plataforma)
                          else if (v.local.isNotEmpty)
                            _info(context, Icons.place_outlined, v.local),
                          if (a == null && v.numParticipantes > 0)
                            _info(
                              context,
                              Icons.group_outlined,
                              v.numParticipantes == 1 ? '1 participante' : '${v.numParticipantes} participantes',
                            ),
                          if (v.calendarioNome.isNotEmpty) _info(context, Icons.event_outlined, v.calendarioNome),
                        ],
                      ),
                      if (a != null && a.convidados.isNotEmpty) _blocoConvidados(context, a, acento),
                      if (a != null && a.convidados.isEmpty && !encerrada)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: onEditar,
                            icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                            label: const Text('Convidar pessoas'),
                            style: TextButton.styleFrom(
                              foregroundColor: c.marca,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      if (v.link != null && !encerrada) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.only(right: a != null ? 6 : 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: v.podeEntrar(agora) ? () => _abrirLink(context, v.link!.url) : null,
                                  icon: const Icon(Icons.login_rounded),
                                  label: Text(v.podeEntrar(agora) ? 'Entrar na reunião' : 'Libera 10 min antes'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(46),
                                    backgroundColor: AppColors.brand,
                                    shape: const StadiumBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: 'Copiar link',
                                onPressed: () => _copiarLink(context, v.link!.url),
                                icon: const Icon(Icons.link_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}