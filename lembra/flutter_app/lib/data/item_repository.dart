import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/item.dart';

/// Persistência local (SQLite). O app funciona 100% offline; a sincronização
/// com o backend envia apenas os itens marcados como "dirty".
class ItemRepository {
  Database? _db;

  Future<Database> get _banco async {
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'lembra.db'),
      version: 2,
      onCreate: (db, versao) async {
        await db.execute('''
          CREATE TABLE itens (
            id TEXT PRIMARY KEY,
            tipo TEXT NOT NULL,
            titulo TEXT NOT NULL,
            inicio INTEGER,
            prazo INTEGER,
            recorrencia TEXT,
            antecedencias TEXT NOT NULL,
            urgencia TEXT NOT NULL,
            status TEXT NOT NULL,
            origem TEXT NOT NULL,
            responsavel TEXT NOT NULL,
            soneca INTEGER NOT NULL DEFAULT 0,
            valor REAL,
            categoria TEXT,
            concluido_em INTEGER,
            criado_em INTEGER NOT NULL,
            atualizado_em INTEGER NOT NULL,
            dirty INTEGER NOT NULL DEFAULT 1
          )
        ''');
      },
      // v2: valor e tipo das contas. Quem já tem o app instalado só ganha as colunas.
      onUpgrade: (db, antiga, nova) async {
        if (antiga < 2) {
          await db.execute('ALTER TABLE itens ADD COLUMN valor REAL');
          await db.execute('ALTER TABLE itens ADD COLUMN categoria TEXT');
        }
      },
    );
  }

  Future<List<Item>> listar({bool incluirCancelados = false}) async {
    final db = await _banco;
    final linhas = await db.query(
      'itens',
      where: incluirCancelados ? null : 'status != ?',
      whereArgs: incluirCancelados ? null : ['cancelado'],
    );
    return linhas.map(Item.fromMap).toList();
  }

  Future<Item?> buscar(String id) async {
    final db = await _banco;
    final l = await db.query('itens', where: 'id = ?', whereArgs: [id], limit: 1);
    return l.isEmpty ? null : Item.fromMap(l.first);
  }

  Future<void> salvar(Item item) async {
    final db = await _banco;
    await db.insert('itens', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Item>> pendentes() async {
    final db = await _banco;
    final l = await db.query('itens', where: 'dirty = 1');
    return l.map(Item.fromMap).toList();
  }

  /// Marca como sincronizados apenas os itens que não mudaram durante o envio.
  Future<void> marcarLimpos(List<Item> enviados) async {
    final db = await _banco;
    final batch = db.batch();
    for (final i in enviados) {
      batch.update(
        'itens',
        {'dirty': 0},
        where: 'id = ? AND atualizado_em = ?',
        whereArgs: [i.id, i.atualizadoEm.millisecondsSinceEpoch],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> marcarTodosSujos() async {
    final db = await _banco;
    await db.update('itens', {'dirty': 1});
  }

  Future<void> limparTudo() async {
    final db = await _banco;
    await db.delete('itens');
  }
}
