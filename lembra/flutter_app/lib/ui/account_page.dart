import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await ref.read(sessaoProvider.notifier).entrar(_email.text.trim(), _senha.text, criar: criar);
    } on ApiErro catch (e) {
      _erro = e.mensagem;
    } catch (_) {
      _erro = 'Não foi possível falar com o servidor. Confira a conexão.';
    }
    if (mounted) setState(() => _ocupado = false);
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
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _senha,
              obscureText: true,
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
