import { randomUUID } from 'node:crypto';
import type { FastifyBaseLogger } from 'fastify';
import { db } from '../db.js';
import { enviarPush } from './push.js';

export interface NovoAviso {
  usuarioId: string;
  reuniaoId: string | null;
  tipo: string;
  titulo: string;
  corpo: string;
  /** Extras que o app recebe junto do push (tudo texto). */
  dados?: Record<string, string>;
}

/** Grava o aviso na central do app e, sem travar quem chamou, manda o push. */
export function criarAviso(a: NovoAviso, log?: FastifyBaseLogger): string {
  const id = randomUUID();
  db.prepare(
    'INSERT INTO avisos (id, usuario_id, reuniao_id, tipo, titulo, corpo, criado_em) VALUES (?, ?, ?, ?, ?, ?, ?)',
  ).run(id, a.usuarioId, a.reuniaoId, a.tipo, a.titulo, a.corpo, Date.now());

  void enviarPush(a.usuarioId, {
    titulo: a.titulo,
    corpo: a.corpo,
    dados: { tipo: a.tipo, avisoId: id, reuniaoId: a.reuniaoId ?? '', ...(a.dados ?? {}) },
  }).catch((e) => log?.warn({ err: e }, 'falha ao enviar push'));

  return id;
}