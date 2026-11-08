import 'dart:async';

import 'package:device_calendar/device_calendar.dart' show Calendar;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/reuniao.dart';
import '../services/calendario_service.dart';
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

final _regexEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String _tituloDia(DateTime dia, DateTime agora) {
  final diff = DateTime.utc(dia.year, dia.month, dia.day)
      .difference(DateTime.utc(agora.year, agora.month, agora.day))
      .inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Amanhã';
  return toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(dia)) ?? '';
}

String _nomeCalendario(Calendar c) {
  final nome = c.name ?? 'Calendário';
  final conta = c.accountName;
  if (conta == null || conta.isEmpty || conta == nome) return nome;
  return '$nome · $conta';
}

Widget _etiqueta(String texto, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(texto, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
    );

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Atualiza a tela a cada 30 s para liberar o botão "Entrar" na hora certa.
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
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

  void _aviso(String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _conectar() async {
    final ok = await ref.read(calendarioServiceProvider).pedirPermissao();
    if (!mounted) return;
    if (!ok) {
      _aviso('Permissão negada. Ative o acesso ao calendário nas configurações do app.');
    }
    ref.invalidate(reunioesProvider);
  }

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
    final criada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.cores.fundo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _FolhaNovaReuniao(servico: svc, calendarios: calendarios),
    );
    if (criada == true) ref.invalidate(reunioesProvider);
  }

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
            Text(titulo,
                textAlign: TextAlign.center,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(texto,
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: c.suave)),
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

  Widget _lista(List<Reuniao> lista) {
    final agora = DateTime.now();
    final porDia = <DateTime, List<Reuniao>>{};
    for (final r in lista) {
      final dia = DateTime(r.inicio.year, r.inicio.month, r.inicio.day);
      (porDia[dia] ??= []).add(r);
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
          _botaoAgendar(),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
              child: Text(
                'Nenhuma reunião nos próximos 30 dias.\nPuxe para baixo para atualizar.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.cores.suave),
              ),
            ),
          for (final e in porDia.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: SectionHeader(_tituloDia(e.key, agora), count: e.value.length),
            ),
            ...e.value.map((r) => _CartaoReuniao(key: ValueKey(r.id), reuniao: r)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(reunioesProvider);
    return estado.when(
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
        return _lista(lista);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cartão de uma reunião
// ---------------------------------------------------------------------------

class _CartaoReuniao extends StatelessWidget {
  const _CartaoReuniao({super.key, required this.reuniao});

  final Reuniao reuniao;

  Future<void> _entrar(BuildContext context) async {
    var abriu = false;
    try {
      abriu = await launchUrl(reuniao.link!.url, mode: LaunchMode.externalApplication);
    } catch (_) {
      abriu = false;
    }
    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Não consegui abrir o link da reunião.')));
    }
  }

  Future<void> _copiar(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: reuniao.link!.url.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Link copiado.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final r = reuniao;
    final hm = DateFormat.Hm('pt_BR');
    final encerrada = DateTime.now().isAfter(r.fim);
    final horario = r.diaInteiro ? 'Dia inteiro' : '${hm.format(r.inicio)} – ${hm.format(r.fim)}';
    final local = r.local?.trim() ?? '';
    final n = r.participantes.length;

    return Opacity(
      opacity: encerrada ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.cartao,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: r.emAndamento ? c.marca : c.borda,
            width: r.emAndamento ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: c.suave),
                const SizedBox(width: 6),
                Text(horario,
                    style: t.labelLarge?.copyWith(color: c.suave, fontWeight: FontWeight.w600)),
                if (r.emAndamento) ...[
                  const SizedBox(width: 8),
                  _etiqueta('Em andamento', c.marca),
                ],
                if (encerrada) ...[
                  const SizedBox(width: 8),
                  _etiqueta('Encerrada', c.suave),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              r.titulo,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.texto),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (r.link != null)
                  _info(context, Icons.videocam_rounded, r.link!.plataforma.nome)
                else if (local.isNotEmpty)
                  _info(context, Icons.place_outlined, local),
                if (n > 0) _info(context, Icons.group_outlined, n == 1 ? '1 participante' : '$n participantes'),
                if (r.calendarioNome.isNotEmpty) _info(context, Icons.event_outlined, r.calendarioNome),
              ],
            ),
            if (r.link != null && !encerrada) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: r.podeEntrar ? () => _entrar(context) : null,
                      icon: const Icon(Icons.login_rounded),
                      label: Text(r.podeEntrar ? 'Entrar na reunião' : 'Libera 10 min antes'),
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
                    onPressed: () => _copiar(context),
                    icon: const Icon(Icons.link_rounded),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Folha "Agendar reunião"
// ---------------------------------------------------------------------------

class _FolhaNovaReuniao extends StatefulWidget {
  const _FolhaNovaReuniao({required this.servico, required this.calendarios});

  final CalendarioService servico;
  final List<Calendar> calendarios;

  @override
  State<_FolhaNovaReuniao> createState() => _FolhaNovaReuniaoState();
}

class _FolhaNovaReuniaoState extends State<_FolhaNovaReuniao> {
  static const _duracoes = {30: '30 min', 45: '45 min', 60: '1 h', 90: '1 h 30', 120: '2 h'};

  final _titulo = TextEditingController();
  final _participantes = TextEditingController();
  final _linkOuLocal = TextEditingController();
  late DateTime _data;
  late TimeOfDay _hora;
  late Calendar _calendario;
  int _duracaoMin = 60;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    // Sugere a próxima meia hora cheia.
    final proxima = agora.add(Duration(minutes: 30 - agora.minute % 30));
    _data = DateTime(proxima.year, proxima.month, proxima.day);
    _hora = TimeOfDay(hour: proxima.hour, minute: proxima.minute);
    _calendario = widget.calendarios.first;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _participantes.dispose();
    _linkOuLocal.dispose();
    super.dispose();
  }

  DateTime get _inicio => DateTime(_data.year, _data.month, _data.day, _hora.hour, _hora.minute);

  InputDecoration _decoracao(String rotulo, {String? ajuda}) {
    final c = context.cores;
    return InputDecoration(
      labelText: rotulo,
      helperText: ajuda,
      helperMaxLines: 2,
      filled: true,
      fillColor: c.cartao,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.borda),
      ),
    );
  }

  /// Chip de escolha (duração e calendário), no mesmo estilo dos filtros da home.
  Widget _opcao(String rotulo, bool selecionado, VoidCallback aoTocar) {
    final c = context.cores;
    return ChoiceChip(
      label: Text(rotulo),
      selected: selecionado,
      showCheckmark: false,
      onSelected: (_) => aoTocar(),
      shape: const StadiumBorder(),
      backgroundColor: c.cartao,
      selectedColor: c.marca.withValues(alpha: 0.18),
      side: BorderSide(color: selecionado ? c.marca : c.borda),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: selecionado ? c.marca : c.texto,
      ),
    );
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: DateTime(hoje.year + 2, hoje.month, hoje.day),
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _escolherHora() async {
    final h = await showTimePicker(context: context, initialTime: _hora);
    if (h != null) setState(() => _hora = h);
  }

  /// Valida, mostra o resumo para confirmação e só então grava no calendário.
  Future<void> _revisar() async {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) {
      setState(() => _erro = 'Dê um título para a reunião.');
      return;
    }
    final emails = _participantes.text.split(RegExp(r'[,;\s]+')).where((e) => e.isNotEmpty).toList();
    final invalidos = emails.where((e) => !_regexEmail.hasMatch(e)).toList();
    if (invalidos.isNotEmpty) {
      setState(() => _erro = 'E-mail inválido: ${invalidos.first}');
      return;
    }
    final inicio = _inicio;
    if (inicio.isBefore(DateTime.now())) {
      setState(() => _erro = 'Escolha um horário no futuro.');
      return;
    }
    setState(() => _erro = null);

    final fim = inicio.add(Duration(minutes: _duracaoMin));
    final hm = DateFormat.Hm('pt_BR');
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar reunião'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(inicio)) ?? ''),
            Text('${hm.format(inicio)} – ${hm.format(fim)}'),
            if (emails.isNotEmpty) Text('Participantes: ${emails.length}'),
            Text('Calendário: ${_nomeCalendario(_calendario)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Agendar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _salvando = true);
    final texto = _linkOuLocal.text.trim();
    final id = await widget.servico.criarReuniao(
      calendarioId: _calendario.id!,
      titulo: titulo,
      inicio: inicio,
      fim: fim,
      descricao: texto.isEmpty ? null : texto,
      local: texto.isEmpty ? null : texto,
      participantes: emails,
    );
    if (!mounted) return;

    if (id == null) {
      setState(() {
        _salvando = false;
        _erro = 'Não foi possível salvar no calendário. Tente escolher outro calendário.';
      });
      return;
    }
    final mensagem = ScaffoldMessenger.of(context);
    final nome = _nomeCalendario(_calendario);
    Navigator.of(context).pop(true);
    mensagem.showSnackBar(SnackBar(content: Text('Reunião agendada em $nome.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cores = context.cores;
    final dataTxt = toBeginningOfSentenceCase(DateFormat("EEE, d 'de' MMM", 'pt_BR').format(_data)) ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Agendar reunião',
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cores.texto)),
              const SizedBox(height: 16),
              TextField(
                controller: _titulo,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoracao('Título'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _escolherData,
                      icon: const Icon(Icons.event_rounded),
                      label: Text(dataTxt),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _escolherHora,
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(_hora.format(context)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Duração', style: t.labelMedium?.copyWith(color: cores.suave)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final e in _duracoes.entries)
                    _opcao(e.value, _duracaoMin == e.key, () => setState(() => _duracaoMin = e.key)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _participantes,
                keyboardType: TextInputType.emailAddress,
                decoration: _decoracao('Participantes', ajuda: 'E-mails separados por vírgula'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _linkOuLocal,
                keyboardType: TextInputType.url,
                decoration: _decoracao(
                  'Link ou local',
                  ajuda: 'Cole o link do Teams, Meet ou Zoom. O Lembra reconhece e mostra o botão Entrar.',
                ),
              ),
              if (widget.calendarios.length > 1) ...[
                const SizedBox(height: 12),
                Text('Salvar no calendário', style: t.labelMedium?.copyWith(color: cores.suave)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final cal in widget.calendarios)
                      _opcao(
                        _nomeCalendario(cal),
                        identical(cal, _calendario),
                        () => setState(() => _calendario = cal),
                      ),
                  ],
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(_erro!, style: t.bodyMedium?.copyWith(color: cores.perigo)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _salvando ? null : _revisar,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.brand,
                  shape: const StadiumBorder(),
                ),
                child: _salvando
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Revisar e agendar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}