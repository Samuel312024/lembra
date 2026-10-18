import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { config } from './config.js';

mkdirSync(dirname(config.DB_PATH), { recursive: true });

// SQLite embutido no Node (sem módulo nativo para compilar no Windows).
export const db = new DatabaseSync(config.DB_PATH);

db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA foreign_keys = ON;

  CREATE TABLE IF NOT EXISTS usuarios (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    senha_hash TEXT NOT NULL,
    criado_em INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS itens (
    id TEXT PRIMARY KEY,
    usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
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
    concluido_em INTEGER,
    criado_em INTEGER NOT NULL,
    atualizado_em INTEGER NOT NULL,
    servidor_em INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_itens_usuario_servidor ON itens(usuario_id, servidor_em);

  CREATE TABLE IF NOT EXISTS uso_ia (
    usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    dia TEXT NOT NULL,
    qtd INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (usuario_id, dia)
  );
`);
