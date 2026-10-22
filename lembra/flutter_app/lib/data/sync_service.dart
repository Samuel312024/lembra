import 'package:shared_preferences/shared_preferences.dart';

import '../domain/item.dart';
import 'api_client.dart';
import 'item_repository.dart';

/// Sincronização simples: envia o que mudou localmente e busca o que mudou no
/// servidor desde a última vez. Em conflito, vence a alteração mais recente.
class SyncService {
  SyncService(this.repo, this.api, this.prefs);

  final ItemRepository repo;
  final ApiClient api;
  final SharedPreferences prefs;

  /// Retorna true se algo mudou localmente (o chamador recarrega a tela e reagenda os alarmes).
  Future<bool> sincronizar() async {
    if (await api.token() == null) return false;
    try {
      final desde = prefs.getInt('sync_desde') ?? 0;
      final pendentes = await repo.pendentes();
      final r = await api.sincronizar(desde, pendentes.map((e) => e.toJson()).toList());
      await repo.marcarLimpos(pendentes);

      var mudou = false;
      for (final bruto in (r['itens'] as List)) {
        final remoto = Item.fromMap((bruto as Map).cast<String, Object?>());
        final local = await repo.buscar(remoto.id);
        if (local == null || remoto.atualizadoEm.isAfter(local.atualizadoEm)) {
          remoto.dirty = false;
          await repo.salvar(remoto);
          mudou = true;
        }
      }
      await prefs.setInt('sync_desde', (r['agora'] as num).toInt());
      return mudou;
    } catch (_) {
      return false; // offline ou servidor fora: tenta de novo depois
    }
  }
}
