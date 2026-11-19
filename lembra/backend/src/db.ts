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
    valor REAL,
    categoria TEXT,
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

// Migração: bancos criados antes de "valor" e "categoria" (contas a pagar) ganham as colunas.
// O SQLite não tem ADD COLUMN IF NOT EXISTS, então confere antes.
const colunasItens = (db.prepare('PRAGMA table_info(itens)').all() as unknown as { name: string }[]).map(
  (c) => c.name,
);
if (!colunasItens.includes('valor')) db.exec('ALTER TABLE itens ADD COLUMN valor REAL');
if (!colunasItens.includes('categoria')) db.exec('ALTER TABLE itens ADD COLUMN categoria TEXT');

// ---------------------------------------------------------------------------
// Convites de reunião: o organizador convida, cada participante responde por um
// link e o organizador recebe a resposta (aviso no app + push).
// Datas em milissegundos (epoch), como nas demais tabelas.
// ---------------------------------------------------------------------------
db.exec(`
  CREATE TABLE IF NOT EXISTS convite_reunioes (
    id TEXT PRIMARY KEY,
    usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    titulo TEXT NOT NULL,
    inicio INTEGER NOT NULL,
    fuso TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
    local TEXT,
    descricao TEXT,
    status TEXT NOT NULL DEFAULT 'ativa',            -- ativa | cancelada
    criado_em INTEGER NOT NULL,
    atualizado_em INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_convite_reunioes_usuario ON convite_reunioes(usuario_id, inicio);

  CREATE TABLE IF NOT EXISTS convite_participantes (
    id TEXT PRIMARY KEY,                              -- também identifica o link de resposta
    reuniao_id TEXT NOT NULL REFERENCES convite_reunioes(id) ON DELETE CASCADE,
    nome TEXT NOT NULL,
    email TEXT,
    telefone TEXT,
    resposta TEXT NOT NULL DEFAULT 'pendente',        -- pendente | aceito | recusado | talvez
    comentario TEXT,
    respondido_em INTEGER,
    enviado_em INTEGER,
    criado_em INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_convite_participantes_reuniao ON convite_participantes(reuniao_id);

  -- Aparelhos do organizador que recebem push (token do Firebase).
  CREATE TABLE IF NOT EXISTS dispositivos (
    token TEXT PRIMARY KEY,
    usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    plataforma TEXT NOT NULL,
    atualizado_em INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_dispositivos_usuario ON dispositivos(usuario_id);

  -- Central de avisos do app (respostas dos convidados etc.).
  CREATE TABLE IF NOT EXISTS avisos (
    id TEXT PRIMARY KEY,
    usuario_id TEXT NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    reuniao_id TEXT REFERENCES convite_reunioes(id) ON DELETE CASCADE,
    tipo TEXT NOT NULL,
    titulo TEXT NOT NULL,
    corpo TEXT NOT NULL,
    criado_em INTEGER NOT NULL,
    lido_em INTEGER
  );
  CREATE INDEX IF NOT EXISTS idx_avisos_usuario ON avisos(usuario_id, criado_em);

  -- Quem pediu para não receber mais convites por e-mail.
  CREATE TABLE IF NOT EXISTS email_bloqueados (
    email TEXT PRIMARY KEY,
    criado_em INTEGER NOT NULL
  );
`);

/** Executa várias escritas como uma só: se uma falhar, nenhuma vale. */
export function transacao<T>(fn: () => T): T {
  db.exec('BEGIN');
  try {
    const resultado = fn();
    db.exec('COMMIT');
    return resultado;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}