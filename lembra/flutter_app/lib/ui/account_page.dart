// Coloque em: lib/ui/account_page.dart  (substitui o arquivo atual)

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/api_client.dart';
import '../state/providers.dart';

/// Conta e sincronização (opcional: o app funciona sem conta).
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _ocupado = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _enviar({required bool criar}) async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final senha = _senha.text;

    // Confere no aparelho antes de chamar o servidor.
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _erro = 'Digite um e-mail válido.');
      return;
    }
    if (senha.length < 8) {
      setState(() => _erro = 'A senha precisa ter pelo menos 8 caracteres.');
      return;
    }

    setState(() {
      _ocupado = true;
      _erro = null;
    });

    String? erro;
    try {
      await ref.read(sessaoProvider.notifier).entrar(email, senha, criar: criar);
    } on ApiErro catch (e) {
      erro = e.mensagem;
    } on TimeoutException {
      erro = 'O servidor demorou para responder. Tente de novo.';
    } on SocketException {
      erro = 'Sem conexão com o servidor. Confira a internet e tente de novo.';
    } on http.ClientException {
      erro = 'Sem conexão com o servidor. Confira a internet e tente de novo.';
    } catch (_) {
      erro = 'Não foi possível falar com o servidor. Confira a conexão.';
    }

    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _erro = erro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(sessaoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Conta e sincronização')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (email != null) ...[
            ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: Text(email),
              subtitle: const Text('Seus itens são sincronizados automaticamente.'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar agora'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(itemsProvider.notifier).sincronizar();
                messenger.showSnackBar(const SnackBar(content: Text('Sincronização concluída.')));
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => ref.read(sessaoProvider.notifier).sair(),
              child: const Text('Sair da conta'),
            ),
          ] else ...[
            const Text(
              'Entre para sincronizar entre aparelhos e liberar o entendimento por IA na nuvem. '
              'Sem conta, tudo continua funcionando só neste aparelho.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _senha,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _ocupado ? null : _enviar(criar: false),
              decoration: const InputDecoration(
                labelText: 'Senha (mínimo 8 caracteres)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _ocupado ? null : () => _enviar(criar: false),
              child: _ocupado
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Entrar'),
            ),
            TextButton(
              onPressed: _ocupado ? null : () => _enviar(criar: true),
              child: const Text('Criar conta'),
            ),
          ],
        ],
      ),
    );
  }
}