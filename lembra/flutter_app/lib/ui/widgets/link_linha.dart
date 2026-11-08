import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Abre o link no navegador (ou no app que o reconhece, como YouTube ou Meet).
Future<void> abrirLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var abriu = false;
  if (uri != null) {
    try {
      abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      abriu = false;
    }
  }
  if (!abriu && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Não consegui abrir o link.')));
  }
}

/// Uma linha de link: tocar no endereço abre; o botão à direita copia
/// (e mostra um "ok" por 2 segundos, já que o aviso de rodapé ficaria atrás do modal).
class LinkLinha extends StatefulWidget {
  const LinkLinha({super.key, required this.url, required this.aoAbrir});

  final String url;
  final VoidCallback aoAbrir;

  @override
  State<LinkLinha> createState() => _LinkLinhaState();
}

class _LinkLinhaState extends State<LinkLinha> {
  bool _copiado = false;

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copiado = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copiado = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: widget.aoAbrir,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                widget.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.marca,
                  decoration: TextDecoration.underline,
                  decorationColor: c.marca,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: _copiado ? 'Copiado' : 'Copiar link',
          visualDensity: VisualDensity.compact,
          icon: Icon(_copiado ? Icons.check_rounded : Icons.copy_rounded, size: 18, color: c.suave),
          onPressed: _copiar,
        ),
      ],
    );
  }
}