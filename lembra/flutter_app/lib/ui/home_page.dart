import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/dinheiro.dart';
import '../domain/draft.dart';
import '../domain/item.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import 'agenda.dart';
import 'conta_paga.dart';
import 'contas_page.dart';
import 'item_form_page.dart';
import 'item_tile.dart';
import 'resumo_contas.dart';
import 'reunioes_page.dart';
import 'review_page.dart';
import 'settings_page.dart';
import 'theme/app_theme.dart';
import 'voice_flow.dart';
import 'widgets/ui_kit.dart';
import '../services/compartilhar_app.dart';

/// Tela "Hoje" (home) com as abas "Próximos" e "Reuniões" e filtro por tipo.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  TipoItem? _filtro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _aoIniciar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) {
      ref.read(itemsProvider.notifier).aoRetomar();
    }
  }

  Future<void> _aoIniciar() async {
    final notif = NotificationService.instance;
    final cfg = ref.read(configProvider);
    await notif.atualizarRotinas(
      briefing: cfg.briefing,
      briefingMin: cfg.briefingMin,
      revisao: cfg.revisao,
      revisaoMin: cfg.revisaoMin,
    );
    await ref.read(itemsProvider.notifier).aoRetomar();
    await notif.verificarLancamento();
    if (mounted) await _permissoesGuiadas();
  }

  /// Na primeira abertura, e em toda abertura enquanto as notificações estiverem
  /// desligadas, explica por que as permissões são necessárias antes de pedir.
  Future<void> _permissoesGuiadas() async {
    final prefs = ref.read(prefsProvider);
    final jaPediu = prefs.getBool('permissoes_pedidas') ?? false;
    final notificacoesOk = await Permission.notification.isGranted;
    if (jaPediu && notificacoesOk) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Vamos configurar os alarmes'),
        content: const Text(
          'O Lembra precisa de permissão para enviar notificações, tocar alarmes no minuto certo e '
          'mostrar o alarme crítico em tela cheia. Sem isso, um lembrete pode falhar justamente quando você precisa.\n\n'
          'O microfone só é usado quando você toca no botão de falar.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Depois')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Permitir')),
          // IconButton(tooltip: 'Compartilhar o Lembra', icon: const Icon(Icons.share_outlined),onPressed: CompartilharApp.compartilhar,),
        ],
      ),
    );
    await prefs.setBool('permissoes_pedidas', true);
    if (ok == true) {
      await NotificationService.instance.pedirPermissoes();
      // Se o Android não mostra mais o pedido (negado antes), leva para os ajustes do app.
      if (await Permission.notification.isPermanentlyDenied) {
        await openAppSettings();
      }
    }
  }

  Future<void> _novoManual() async {
    final d = await Navigator.of(context).push<Draft>(MaterialPageRoute(builder: (_) => const ItemFormPage()));
    if (d != null) await ref.read(itemsProvider.notifier).criar(d);
  }

  Future<void> _editar(Item item) async {
    final d = await Navigator.of(context).push<Draft>(
      MaterialPageRoute(builder: (_) => ItemFormPage(rascunho: Draft.deItem(item), titulo: 'Editar lembrete')),
    );
    if (d != null) await ref.read(itemsProvider.notifier).atualizarDe(item.id, d);
  }

  Future<void> _concluir(Item item) async {
    final antes = await ref.read(itemsProvider.notifier).concluir(item.id);
    if (!mounted) return;
    avisarConcluido(context, ref, item, antes);
  }

  Future<void> _cancelar(Item item) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(itemsProvider.notifier);
    final antes = await notifier.cancelar(item.id);
    messenger.showSnackBar(SnackBar(
      content: Text('“${item.titulo}” cancelado.'),
      action: antes == null ? null : SnackBarAction(label: 'Desfazer', onPressed: () => notifier.restaurar(antes)),
    ));
  }

  void _lerDia() {
    final itens = ref.read(itemsProvider).valueOrNull ?? [];
    final agora = DateTime.now();
    ref.read(ttsProvider).falar(textoResumo(itens, agora, agora));
  }

  ItemTile _tile(Item i, {bool feito = false}) => ItemTile(
        key: ValueKey('${i.id}-$feito'),
        item: i,
        feito: feito,
        onTap: () => _abrirDetalhes(i, feito: feito),
        onConcluir: () => _concluir(i),
        onCancelar: () => _cancelar(i),
      );

  // -------------------------------------------------------------------------
  // Detalhes do item (modal)
  // -------------------------------------------------------------------------

  /// Toque no card: abre um modal com tudo o que está escrito no item, sem corte,
  /// para dar para ler com calma. De lá o usuário edita, conclui ou cancela.
  void _abrirDetalhes(Item item, {bool feito = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.cores.fundo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => _detalhesItem(ctx, item, feito),
    );
  }

  /// Uma linha do modal: ícone, rótulo pequeno e o texto inteiro (selecionável).
  Widget _linhaDetalhe(BuildContext ctx, IconData icone, String rotulo, String texto) {
    final t = Theme.of(ctx).textTheme;
    final c = ctx.cores;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: c.suave),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: t.labelMedium?.copyWith(color: c.suave)),
                const SizedBox(height: 2),
                SelectableText(texto, style: t.bodyLarge?.copyWith(color: c.texto)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detalhesItem(BuildContext ctx, Item item, bool feito) {
    final t = Theme.of(ctx).textTheme;
    final c = ctx.cores;
    String maiuscula(String s) => toBeginningOfSentenceCase(s) ?? s;

    final a = item.ancora;
    final String quando;
    if (a == null) {
      quando = 'Sem data';
    } else if (a.hour == 0 && a.minute == 0) {
      quando = '${maiuscula(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(a))} • sem horário definido';
    } else {
      quando = maiuscula(DateFormat("EEEE, d 'de' MMMM 'às' HH:mm", 'pt_BR').format(a));
    }

    final repete = item.regra?.descricao;
    final mostrarValor = item.tipo == TipoItem.conta && item.valor != null;
    final urgencia = switch (item.urgencia) {
      Urgencia.discreto => 'Discreto (sem som)',
      Urgencia.normal => 'Normal',
      Urgencia.critico => 'Crítico (alarme com som)',
    };

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.tipo.rotulo.toUpperCase(),
                style: t.labelLarge?.copyWith(
                  color: c.marca,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                item.titulo,
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: c.texto),
              ),
              _linhaDetalhe(ctx, Icons.event_rounded, 'Quando', quando),
              if (repete != null && repete.isNotEmpty)
                _linhaDetalhe(ctx, Icons.repeat_rounded, 'Repete', repete),
              if (mostrarValor)
                _linhaDetalhe(ctx, Icons.account_balance_wallet_rounded, 'Valor', formatarReais(item.valor!)),
              _linhaDetalhe(ctx, Icons.notifications_active_outlined, 'Aviso', urgencia),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _editar(item);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.brand,
                  shape: const StadiumBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (!feito) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _concluir(item);
                        },
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Feito'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _cancelar(item);
                      },
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancelar'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: c.perigo,
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Visual
  // -------------------------------------------------------------------------

  String _saudacao() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _dataHoje() => DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(DateTime.now());

  Widget _acao(IconData icone, String dica, VoidCallback aoTocar) => IconButton.filled(
        tooltip: dica,
        onPressed: aoTocar,
        icon: Icon(icone, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.cream,
          foregroundColor: AppColors.ink,
          visualDensity: VisualDensity.compact,
        ),
      );

  /// Chip de filtro. O nome nunca é cortado dentro do chip: sem quebra de
  /// linha e sem reticências. Se a faixa não couber na tela, quem rola para o
  /// lado é a faixa (veja o build), não o texto.
  Widget _chip(String rotulo, bool selecionado, VoidCallback aoTocar) {
    final c = context.cores;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          rotulo,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
        selected: selecionado,
        onSelected: (_) => aoTocar(),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        backgroundColor: c.cartao,
        selectedColor: c.marca.withValues(alpha: 0.18),
        side: BorderSide(color: selecionado ? c.marca : c.borda),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: selecionado ? c.marca : c.texto,
        ),
      ),
    );
  }

  Widget _secao(String titulo, int quantidade) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: SectionHeader(titulo, count: quantidade),
      );

  Widget _vazio() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconBadge(icon: Icons.mic_none_rounded, color: AppColors.orange, size: 72),
              const SizedBox(height: 16),
              Text(
                'Nada por aqui',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Toque em “Falar agora” e diga, por exemplo:\n“Tenho médico dia 22 às 14h30”.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.cores.suave),
              ),
            ],
          ),
        ),
      );

  Widget _semResultadoNoFiltro() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
        child: Center(
          child: Text(
            'Nenhum item deste tipo hoje.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.cores.suave),
          ),
        ),
      );

  /// Próximo item com horário definido, olhando hoje e os dias seguintes.
  Item? _proximoAlarme(List<Item> itens, DateTime agora) {
    final hoje = agruparHoje(itens, agora);
    final prox = agruparProximos(itens, agora);
    final candidatos = <Item>[
      ...hoje.hoje,
      for (final lista in prox.porDia.values) ...lista,
    ].where((i) {
      final a = i.ancora;
      return a != null && a.isAfter(agora) && (a.hour != 0 || a.minute != 0);
    });

    Item? melhor;
    for (final i in candidatos) {
      if (melhor == null || i.ancora!.isBefore(melhor.ancora!)) melhor = i;
    }
    return melhor;
  }

  /// Itens vencidos ou críticos que merecem atenção agora.
  List<Item> _criticosProximos(List<Item> itens, DateTime agora) {
    final limite = agora.add(const Duration(hours: 24));
    final lista = itens.where((i) {
      final a = i.ancora;
      return i.status == StatusItem.ativo &&
          i.urgencia == Urgencia.critico &&
          a != null &&
          a.isAfter(agora) &&
          a.isBefore(limite);
    }).toList();
    lista.sort((x, y) => x.ancora!.compareTo(y.ancora!));
    return lista;
  }

  bool _temAlerta(List<Item> itens) {
    final agora = DateTime.now();
    return agruparHoje(itens, agora).atrasados.isNotEmpty || _criticosProximos(itens, agora).isNotEmpty;
  }

  /// Sino do topo: bolinha vermelha quando há atrasados ou críticos nas próximas 24 h.
  Widget _sino(bool alerta) => Stack(
        clipBehavior: Clip.none,
        children: [
          _acao(Icons.notifications_none_rounded, 'Precisa de atenção', _abrirAtencao),
          if (alerta)
            Positioned(
              right: 6,
              top: 6,
              child: IgnorePointer(
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cream, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      );

  void _abrirAtencao() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.cores.fundo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Consumer(
        builder: (ctx, r, _) {
          final lista = r.watch(itemsProvider).valueOrNull ?? const <Item>[];
          final agora = DateTime.now();
          final atrasados = agruparHoje(lista, agora).atrasados;
          final criticos = _criticosProximos(lista, agora);
          final t = Theme.of(ctx).textTheme;
          final c = ctx.cores;

          Widget tile(Item i) => ItemTile(
                key: ValueKey('atencao-${i.id}'),
                item: i,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _abrirDetalhes(i);
                },
                onConcluir: () => _concluir(i),
                onCancelar: () => _cancelar(i),
              );

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(
                    'Precisa de atenção',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (atrasados.isEmpty && criticos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                    child: Column(
                      children: [
                        const IconBadge(icon: Icons.check_rounded, color: AppColors.green, size: 64),
                        const SizedBox(height: 16),
                        Text('Tudo em dia', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          'Nada atrasado e nenhum alarme crítico nas próximas 24 horas.',
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(color: c.suave),
                        ),
                      ],
                    ),
                  ),
                if (atrasados.isNotEmpty) ...[
                  _secao('Atrasados', atrasados.length),
                  ...atrasados.map(tile),
                ],
                if (criticos.isNotEmpty) ...[
                  _secao('Críticos nas próximas 24 h', criticos.length),
                  ...criticos.map(tile),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Card "Contas a vencer": soma dos valores das contas em aberto (vencidas e
  /// futuras). Tocar abre a lista de contas.
  Widget _cardContas(List<Item> itens, DateTime agora) {
    final r = ResumoContas.de(itens, agora);
    final qtd = r.quantidade;
    final venc = r.vencidas.length;
    final vencidas = venc == 1 ? '1 vencida' : '$venc vencidas';

    final String valor;
    final String legenda;
    if (qtd == 0) {
      valor = formatarReais(0);
      legenda = 'Nenhuma conta em aberto';
    } else if (!r.temValor) {
      valor = '$qtd';
      legenda = [
        qtd == 1 ? 'conta sem valor informado' : 'contas sem valor informado',
        if (venc > 0) vencidas,
      ].join(' • ');
    } else {
      valor = formatarReais(r.total);
      legenda = [
        qtd == 1 ? '1 conta' : '$qtd contas',
        if (venc > 0) vencidas,
        if (r.semValor > 0) '${r.semValor} sem valor',
      ].join(' • ');
    }

    final c = context.cores;
    return StatCard(
      icon: Icons.account_balance_wallet_rounded,
      iconColor: AppColors.yellow,
      label: 'Contas a vencer',
      value: valor,
      valueColor: venc > 0 ? c.perigo : c.ciano,
      caption: legenda,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContasPage())),
    );
  }

  Widget _resumoDoDia(List<Item> itens, DateTime agora) {
    final todos = agruparHoje(itens, agora);
    final feitos = todos.feitos.length;
    final atrasados = todos.atrasados.length;
    final pendentes = atrasados + todos.hoje.length;
    final total = pendentes + feitos;
    final progresso = total == 0 ? 0.0 : feitos / total;
    final titulo = atrasados > 0
        ? 'Há itens atrasados'
        : (feitos == total ? 'Dia concluído' : 'Dia sob controle');

    final proximo = _proximoAlarme(itens, agora);
    final quando = proximo?.ancora;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          DayGauge(progress: progresso, done: feitos, total: total, title: titulo),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    icon: Icons.alarm_rounded,
                    iconColor: AppColors.orange,
                    label: proximo?.titulo ?? 'Próximo alarme',
                    value: quando == null ? '--:--' : DateFormat.Hm('pt_BR').format(quando),
                    valueColor: context.cores.marca,
                    caption: quando == null
                        ? 'Nenhum alarme à frente'
                        : 'Próximo alarme • ${quandoCurto(quando, comHora: false, agora: agora)}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _cardContas(itens, agora)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _abaHoje(List<Item> itens) {
    final agora = DateTime.now();
    final todos = agruparHoje(itens, agora);
    if (todos.vazio) return _vazio();

    final g = _filtro == null ? todos : agruparHoje(itens, agora, filtro: _filtro);

    return ListView(
      padding: const EdgeInsets.only(bottom: 200),
      children: [
        _resumoDoDia(itens, agora),
        if (g.vazio) _semResultadoNoFiltro(),
        if (g.atrasados.isNotEmpty) ...[
          _secao('Atrasados', g.atrasados.length),
          ...g.atrasados.map(_tile),
        ],
        if (g.hoje.isNotEmpty) ...[
          _secao('Hoje', g.hoje.length),
          ...g.hoje.map(_tile),
        ],
        if (g.feitos.isNotEmpty) ...[
          _secao('Feitos hoje', g.feitos.length),
          ...g.feitos.map((i) => _tile(i, feito: true)),
        ],
      ],
    );
  }

  Widget _abaProximos(List<Item> itens) {
    final g = agruparProximos(itens, DateTime.now(), filtro: _filtro);
    if (g.vazio) return _vazio();
    final agora = DateTime.now();
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 200),
      children: [
        for (final e in g.porDia.entries) ...[
          _secao(
            toBeginningOfSentenceCase(quandoCurto(e.key, comHora: false, agora: agora)) ?? '',
            e.value.length,
          ),
          ...e.value.map(_tile),
        ],
        if (g.semData.isNotEmpty) ...[
          _secao('Sem data', g.semData.length),
          ...g.semData.map(_tile),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final itens = ref.watch(itemsProvider);
    final t = Theme.of(context).textTheme;
    final alerta = _temAlerta(itens.valueOrNull ?? const <Item>[]);
    final c = context.cores;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          body: Column(
            children: [
              HeroPanel(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _saudacao(),
                                style: t.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.onDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _dataHoje(),
                                style: t.bodySmall?.copyWith(color: AppColors.onDarkMuted),
                              ),
                            ],
                          ),
                        ),
                        _sino(alerta),
                        _acao(Icons.volume_up_outlined, 'Ouvir o resumo do dia', _lerDia),
                        _acao(
                          Icons.fact_check_outlined,
                          'Revisão do dia',
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewPage())),
                        ),
                        _acao(
                          Icons.settings_outlined,
                          'Ajustes',
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            padding: EdgeInsets.zero,
                            labelPadding: EdgeInsets.only(right: 24),
                            dividerColor: Colors.transparent,
                            indicatorColor: AppColors.brandSoft,
                            indicatorWeight: 3,
                            indicatorSize: TabBarIndicatorSize.label,
                            labelColor: AppColors.onDark,
                            unselectedLabelColor: AppColors.onDarkMuted,
                            labelStyle: TextStyle(fontWeight: FontWeight.w700),
                            tabs: [Tab(text: 'Hoje'), Tab(text: 'Próximos'), Tab(text: 'Reuniões')],
                          ),
                        ),
                        _acao(Icons.share_outlined, 'Compartilhar o Lembra', CompartilharApp.compartilhar),
                      ],
                    ),
                  ],
                ),
              ),
              // Filtros por tipo: uma linha só, desliza com o dedo para o lado.
              // O nome dentro de cada chip nunca é cortado (veja _chip).
              // Ficam escondidos na aba "Reuniões" (índice 2), onde não se aplicam.
              Builder(
                builder: (ctx) {
                  final aba = DefaultTabController.of(ctx);
                  return AnimatedBuilder(
                    animation: aba,
                    builder: (_, filtros) => aba.index == 2 ? const SizedBox.shrink() : filtros!,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _chip('Todos', _filtro == null, () => setState(() => _filtro = null)),
                          for (final tipo in TipoItem.values)
                            _chip(
                              tipo.rotulo,
                              _filtro == tipo,
                              () => setState(() => _filtro = _filtro == tipo ? null : tipo),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Expanded(
                child: itens.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Erro ao carregar: $e')),
                  data: (lista) => TabBarView(
                    children: [_abaHoje(lista), _abaProximos(lista), const ReunioesPage()],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'manual',
                tooltip: 'Adicionar digitando',
                onPressed: _novoManual,
                backgroundColor: c.cartao,
                foregroundColor: c.marca,
                elevation: 1,
                child: const Icon(Icons.edit_outlined),
              ),
              const SizedBox(height: 12),
              VoiceFab(onPressed: () => iniciarVoz(context, ref)),
            ],
          ),
        ),
      ),
    );
  }
}