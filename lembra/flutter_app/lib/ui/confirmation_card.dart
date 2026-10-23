import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app.dart';
import '../domain/categoria_conta.dart';
import '../domain/dinheiro.dart';
import '../domain/draft.dart';
import '../domain/item.dart';
import '../domain/recorrencia.dart';
import '../nlp/comandos.dart';
import 'agenda.dart';
import 'item_form_page.dart';
import 'item_tile.dart' show iconeDaCategoria;
import 'voice_sheet.dart';

/// Cartão de confirmação: mostra o que foi entendido. Nada é agendado sem
/// o usuário confirmar. Devolve o rascunho (possivelmente editado) ou null se descartado.
Future<Draft?> mostrarCartao(BuildContext context, Draft draft, {int indice = 1, int total = 1}) {
  return showModalBottomSheet<Draft>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: true,
    builder: (_) => _Cartao(draft: draft, indice: indice, total: total),
  );
}

class _Cartao extends StatefulWidget {
  const _Cartao({required this.draft, required this.indice, required this.total});
  final Draft draft;
  final int indice;
  final int total;

  @override
  State<_Cartao> createState() => _CartaoState();
}

class _CartaoState extends State<_Cartao> {
  late Draft d = widget.draft;
  late final TextEditingController _titulo = TextEditingController(text: d.titulo);

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  void _mudarTipo(TipoItem t) {
    setState(() {
      final a = d.ancora;
      d.tipo = t;
      d.definirAncora(a);
      d.antecedencias = Draft.antecedenciasPadrao(t);
    });
  }

  bool get _temHorario => !d.camposFaltando.contains('horario');

  String _textoQuando() {
    final a = d.ancora;
    if (a == null) return 'Sem data';
    final base = quandoCurto(a, comHora: _temHorario);
    return d.recorrencia != null ? 'Começa: $base' : base;
  }

  String _textoAvisos() {
    if (d.ancora == null) return 'Sem avisos (não há data)';
    if (d.antecedencias.isEmpty) return 'Sem avisos';
    final ord = [...d.antecedencias]..sort((a, b) => b.compareTo(a));
    return 'Avisos: ${ord.map(_rotuloAntecedencia).join(', ')}';
  }

  String _rotuloAntecedencia(int m) {
    if (m == 0) return 'no horário';
    if (m % 1440 == 0) return '${m ~/ 1440} dia${m ~/ 1440 > 1 ? 's' : ''} antes';
    if (m % 60 == 0) return '${m ~/ 60} h antes';
    return '$m min antes';
  }

  String _textoConta() {
    final tipo = d.categoria?.rotulo ?? 'Tipo de conta não informado';
    final valor = d.valor == null ? 'valor não informado' : formatarReais(d.valor!);
    return '$tipo • $valor';
  }

  Future<void> _alterarQuando() async {
    final agora = DateTime.now();
    final atual = d.ancora ?? agora;
    final data = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(agora.year, agora.month, agora.day - 1),
      lastDate: DateTime(agora.year + 5),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: atual.hour == 0 ? 9 : atual.hour, minute: atual.minute),
    );
    if (hora == null || !mounted) return;
    setState(() {
      d.definirAncora(DateTime(data.year, data.month, data.day, hora.hour, hora.minute));
      d.camposFaltando.removeWhere((c) => c == 'data' || c == 'horario');
      d.horarioPadrao = false;
      d.ambiguidade = Ambiguidade.nenhuma;
    });
  }

  Future<void> _editar() async {
    d.titulo = _titulo.text;
    final r = await Navigator.of(context).push<Draft>(
      MaterialPageRoute(builder: (_) => ItemFormPage(rascunho: d, titulo: 'Editar lembrete')),
    );
    if (r != null && mounted) {
      setState(() {
        d = r;
        _titulo.text = r.titulo;
      });
    }
  }

  Future<void> _porVoz() async {
    final texto = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const VoiceSheet(
        titulo: 'Diga o que fazer',
        dica: '“confirma”, “edita” ou “descarta”',
      ),
    );
    if (texto == null || !mounted) return;
    switch (interpretarResposta(texto)) {
      case RespostaVoz.confirmar:
        _confirmar();
      case RespostaVoz.descartar:
        Navigator.of(context).pop();
      case RespostaVoz.editar:
        await _editar();
      case RespostaVoz.desconhecida:
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Não entendi. Toque em Confirmar, Editar ou Descartar.')));
    }
  }

  void _confirmar() {
    d.titulo = _titulo.text.trim();
    if (d.titulo.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dê um nome ao lembrete.')));
      return;
    }
    Navigator.of(context).pop(d);
  }

  List<String> _avisos() {
    final out = <String>[];
    final a = d.ancora;
    if (d.horarioPadrao && a != null) {
      out.add('Você não informou o horário: usei ${DateFormat.Hm('pt_BR').format(a)} (padrão).');
    }
    if (a != null && d.recorrencia == null && a.isBefore(DateTime.now())) {
      out.add('Esse horário já passou — nenhum aviso será disparado.');
    }
    if (a == null && (d.tipo == TipoItem.compromisso || d.recorrencia != null)) {
      out.add('Sem data: o item ficará só na lista, sem alarme.');
    }
    if (!_temHorario && !d.horarioPadrao) out.add('Falta o horário.');
    if (d.tipo == TipoItem.conta && d.valor == null) {
      out.add('Conta sem valor: toque em “Informar” para ela entrar no total.');
    }
    if (d.confianca < 0.6) out.add('Não tenho certeza do que entendi — confira antes de confirmar.');
    return out;
  }

  Widget _linha(IconData icone, String texto, {VoidCallback? acao, String? rotulo}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icone, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(texto)),
          if (acao != null) TextButton(onPressed: acao, child: Text(rotulo ?? 'Alterar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rec = Recorrencia.parse(d.recorrencia);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary),
                const SizedBox(width: 8),
                Text('Entendi assim', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (widget.total > 1) Text('${widget.indice} de ${widget.total}'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final t in TipoItem.values)
                  ChoiceChip(label: Text(t.rotulo), selected: d.tipo == t, onSelected: (_) => _mudarTipo(t)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titulo,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'O quê', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            _linha(Icons.event_outlined, _textoQuando(), acao: _alterarQuando),
            if (rec != null) _linha(Icons.repeat, rec.descricao),
            if (d.tipo == TipoItem.conta)
              _linha(
                d.categoria == null ? Icons.receipt_long_outlined : iconeDaCategoria(d.categoria!),
                _textoConta(),
                acao: _editar,
                rotulo: (d.categoria == null || d.valor == null) ? 'Informar' : 'Alterar',
              ),
            _linha(Icons.notifications_active_outlined, _textoAvisos()),
            const SizedBox(height: 8),
            SegmentedButton<Urgencia>(
              segments: [
                for (final u in Urgencia.values) ButtonSegment(value: u, label: Text(u.rotulo)),
              ],
              selected: {d.urgencia},
              onSelectionChanged: (s) => setState(() => d.urgencia = s.first),
            ),
            for (final a in _avisos())
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: corCritico),
                    const SizedBox(width: 8),
                    Expanded(child: Text(a, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _confirmar,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirmar'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Responder por voz',
                  onPressed: _porVoz,
                  icon: const Icon(Icons.mic),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _editar, child: const Text('Editar')),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Descartar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Faz UMA pergunta curta quando falta algo essencial, em vez de chutar.
/// Retorna o rascunho atualizado ou null se o usuário dispensou a pergunta.
Future<Draft?> perguntarLacuna(BuildContext context, Draft d, int horarioPadraoMin) {
  return showModalBottomSheet<Draft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Pergunta(draft: d, horarioPadraoMin: horarioPadraoMin),
  );
}

class _Pergunta extends StatelessWidget {
  const _Pergunta({required this.draft, required this.horarioPadraoMin});
  final Draft draft;
  final int horarioPadraoMin;

  DateTime _comHora(DateTime dia, DateTime? ref) =>
      DateTime(dia.year, dia.month, dia.day, ref?.hour ?? 0, ref?.minute ?? 0);

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final tipo = d.proximaPergunta;
    final String texto;
    final chips = <Widget>[];

    void concluir(Draft r) => Navigator.of(context).pop(r);

    switch (tipo) {
      case TipoPergunta.hojeOuProxima:
        final proxima = d.ancora!;
        final hoje = d.alternativaData!;
        final nome = DateFormat('EEEE', 'pt_BR').format(proxima);
        texto = '“$nome”: é hoje ou na próxima?';
        chips.add(ActionChip(
          label: Text('Hoje (${DateFormat('dd/MM').format(hoje)})'),
          onPressed: () {
            d.definirAncora(_comHora(hoje, proxima));
            d.ambiguidade = Ambiguidade.nenhuma;
            concluir(d);
          },
        ));
        chips.add(ActionChip(
          label: Text('Dia ${DateFormat('dd/MM').format(proxima)}'),
          onPressed: () {
            d.ambiguidade = Ambiguidade.nenhuma;
            concluir(d);
          },
        ));
      case TipoPergunta.data:
        texto = 'Para quando?';
        final agora = DateTime.now();
        void definir(DateTime dia) {
          d.definirAncora(_comHora(dia, d.ancora));
          d.camposFaltando.remove('data');
          // sem horário ainda: a próxima pergunta será "Que horas?"
          if (d.ancora != null && !d.camposFaltando.contains('horario')) d.camposFaltando.add('horario');
          concluir(d);
        }
        chips.add(ActionChip(label: const Text('Hoje'), onPressed: () => definir(inicioDoDia(agora))));
        chips.add(ActionChip(
          label: const Text('Amanhã'),
          onPressed: () => definir(DateTime(agora.year, agora.month, agora.day + 1)),
        ));
        chips.add(ActionChip(
          label: const Text('Escolher data…'),
          onPressed: () async {
            final r = await showDatePicker(
              context: context,
              initialDate: agora,
              firstDate: agora,
              lastDate: DateTime(agora.year + 5),
            );
            if (r != null) definir(r);
          },
        ));
      case TipoPergunta.horario:
      case null:
        texto = 'Que horas?';
        final base = d.ancora ?? inicioDoDia(DateTime.now());
        void definirHora(int h, int m, {bool padrao = false}) {
          d.definirAncora(DateTime(base.year, base.month, base.day, h, m));
          d.camposFaltando.remove('horario');
          d.horarioPadrao = padrao;
          concluir(d);
        }
        chips.add(ActionChip(
          label: Text('${horaMinutos(horarioPadraoMin)} (padrão)'),
          onPressed: () => definirHora(horarioPadraoMin ~/ 60, horarioPadraoMin % 60, padrao: true),
        ));
        for (final h in const [12, 18]) {
          chips.add(ActionChip(label: Text('${h.toString().padLeft(2, '0')}:00'), onPressed: () => definirHora(h, 0)));
        }
        chips.add(ActionChip(
          label: const Text('Escolher horário…'),
          onPressed: () async {
            final r = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: horarioPadraoMin ~/ 60, minute: horarioPadraoMin % 60),
            );
            if (r != null) definirHora(r.hour, r.minute);
          },
        ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.titulo, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(texto, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }
}