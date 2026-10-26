// Coloque em: lib/ui/dados_page.dart
//
// Ajustes > Dados e diagnóstico: backup dos lembretes e relatório de erros.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/item.dart';
import '../services/diagnostico.dart';
import '../state/providers.dart';

class DadosPage extends ConsumerStatefulWidget {
  const DadosPage({super.key});

  @override
  ConsumerState<DadosPage> createState() => _DadosPageState();
}

class _DadosPageState extends ConsumerState<DadosPage> {
  void _aviso(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _copiarBackup() async {
    final itens = await ref.read(repoProvider).listar();
    final json = jsonEncode({
      'app': 'lembra',
      'versao': 1,
      'gerado_em': DateTime.now().toIso8601String(),
      'itens': [for (final i in itens) i.toMap()],
    });
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    _aviso('Backup de ${itens.length} item(ns) copiado. Cole em um lugar seguro (notas, e-mail).');
  }

  Future<void> _restaurarBackup() async {
    final controle = TextEditingController();
    final colado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controle,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Cole aqui o backup copiado do Lembra',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controle.text), child: const Text('Restaurar')),
        ],
      ),
    );
    controle.dispose();
    if (colado == null || colado.trim().isEmpty) return;

    try {
      final dados = jsonDecode(colado) as Map<String, dynamic>;
      if (dados['app'] != 'lembra') throw const FormatException('não é um backup do Lembra');
      final itens = [
        for (final m in (dados['itens'] as List)) Item.fromMap((m as Map).cast<String, Object?>()),
      ];
      final repo = ref.read(repoProvider);
      for (final i in itens) {
        await repo.salvar(i);
      }
      await repo.marcarTodosSujos(); // se houver conta, tudo é enviado ao servidor
      ref.invalidate(itemsProvider);
      await ref.read(itemsProvider.future);
      await ref.read(itemsProvider.notifier).reagendarNotificacoes();
      if (!mounted) return;
      _aviso('${itens.length} item(ns) restaurado(s).');
    } catch (_) {
      if (!mounted) return;
      _aviso('Não consegui ler esse backup. Confira se você colou o texto inteiro.');
    }
  }

  Future<void> _verRelatorio() async {
    final erros = Diagnostico.erros();
    if (erros.isEmpty) {
      _aviso('Nenhum problema registrado.');
      return;
    }
    final texto = erros.reversed.join('\n\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Últimos problemas (${erros.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(texto, style: const TextStyle(fontSize: 12))),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texto));
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) _aviso('Relatório copiado.');
            },
            child: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () async {
              await Diagnostico.limpar();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) setState(() {});
            },
            child: const Text('Limpar'),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qtd = Diagnostico.erros().length;
    return Scaffold(
      appBar: AppBar(title: const Text('Dados e diagnóstico')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Backup: guarde seus lembretes fora do aparelho. Se você tem conta no Lembra, '
              'eles também ficam salvos no servidor.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: const Text('Copiar backup'),
            subtitle: const Text('Copia todos os seus lembretes como texto'),
            onTap: _copiarBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restaurar backup'),
            subtitle: const Text('Cole um backup copiado antes'),
            onTap: _restaurarBackup,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Relatório de problemas'),
            subtitle: Text(qtd == 0 ? 'Nenhum problema registrado' : '$qtd registrado(s) neste aparelho'),
            onTap: _verRelatorio,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Os problemas ficam só neste aparelho. Se precisar de ajuda, copie o relatório e envie para o suporte.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}