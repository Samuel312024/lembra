// Coloque em: lembra/backend/src/rotas/convites.ts  (substitui o arquivo atual)

import { randomUUID } from 'node:crypto';
import type { FastifyBaseLogger, FastifyInstance } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import { db, transacao } from '../db.js';
import { emailConfigurado, enviarEmail } from '../servicos/email.js';
import { pushConfigurado } from '../servicos/push.js';
import { linkConvite } from '../servicos/token.js';
import { montarEmail, type Resposta, type TipoEmail } from '../servicos/textos.js';
import { sendToMake } from '../servicos/make.js';

type ReuniaoRow = {
  id: string;
  usuario_id: string;
  titulo: string;
  inicio: number;
  fuso: string;
  local: string | null;
  descricao: string | null;
  status: 'ativa' | 'cancelada';
  criado_em: number;
  atualizado_em: number;
};

type ParticipanteRow = {
  id: string;
  reuniao_id: string;
  nome: string;
  email: string | null;
  telefone: string | null;
  resposta: Resposta;
  comentario: string | null;
  respondido_em: number | null;
  enviado_em: number | null;
  criado_em: number;
};

const UM_DIA = 24 * 60 * 60 * 1000;
const INTERVALO_REENVIO = 10 * 60 * 1000;

// ---------------------------------------------------------------------------
// Validação
// ---------------------------------------------------------------------------

const fusoValido = z
  .string()
  .max(60)
  .refine((f) => {
    try {
      new Intl.DateTimeFormat('pt-BR', { timeZone: f });
      return true;
    } catch {
      return false;
    }
  }, 'fuso inválido');

const participanteEsquema = z
  .object({
    nome: z.string().trim().min(1).max(120),
    email: z.string().trim().toLowerCase().email().max(200).optional(),
    telefone: z.string().trim().min(1).max(30).optional(),
  })
  .refine((p) => p.email || p.telefone, { message: 'informe e-mail ou telefone' });

const novaReuniaoEsquema = z.object({
  titulo: z.string().trim().min(1).max(200),
  inicio: z.string().datetime({ offset: true }),
  fuso: fusoValido.default('America/Sao_Paulo'),
  local: z.string().trim().max(500).optional(),
  descricao: z.string().trim().max(2000).optional(),
  participantes: z.array(participanteEsquema).min(1).max(50),
});

const edicaoEsquema = z
  .object({
    titulo: z.string().trim().min(1).max(200),
    inicio: z.string().datetime({ offset: true }),
    fuso: fusoValido,
    local: z.string().trim().max(500).nullable(),
    descricao: z.string().trim().max(2000).nullable(),
  })
  .partial()
  .refine((o) => Object.keys(o).length > 0, { message: 'nada para alterar' });

const idEsquema = z.object({ id: z.string().uuid() });

// ---------------------------------------------------------------------------
// Acesso ao banco
// ---------------------------------------------------------------------------

const iso = (ms: number | null) => (ms === null ? null : new Date(ms).toISOString());

function buscarReuniao(id: string, usuarioId: string): ReuniaoRow | undefined {
  return db.prepare('SELECT * FROM convite_reunioes WHERE id = ? AND usuario_id = ?').get(id, usuarioId) as
    | ReuniaoRow
    | undefined;
}

function participantesDe(reuniaoId: string): ParticipanteRow[] {
  return db
    .prepare('SELECT * FROM convite_participantes WHERE reuniao_id = ? ORDER BY criado_em ASC, nome ASC')
    .all(reuniaoId) as unknown as ParticipanteRow[];
}

function emailDoUsuario(usuarioId: string): string {
  const u = db.prepare('SELECT email FROM usuarios WHERE id = ?').get(usuarioId) as { email: string } | undefined;
  return u?.email ?? '';
}

/** Versão enxuta da reunião para o Make: sem links e sem telefones. */
function paraMake(r: ReuniaoRow, ps: ParticipanteRow[]) {
  return {
    id: r.id,
    titulo: r.titulo,
    inicio: iso(r.inicio),
    fuso: r.fuso,
    local: r.local,
    descricao: r.descricao,
    status: r.status,
    participantes: ps.map((p) => ({ nome: p.nome, email: p.email, resposta: p.resposta })),
  };
}

function serializar(r: ReuniaoRow, ps: ParticipanteRow[]) {
  const resumo: Record<Resposta, number> = { aceito: 0, recusado: 0, talvez: 0, pendente: 0 };
  for (const p of ps) resumo[p.resposta]++;
  return {
    id: r.id,
    titulo: r.titulo,
    inicio: iso(r.inicio),
    fuso: r.fuso,
    local: r.local,
    descricao: r.descricao,
    status: r.status,
    resumo,
    participantes: ps.map((p) => ({
      id: p.id,
      nome: p.nome,
      email: p.email,
      telefone: p.telefone,
      resposta: p.resposta,
      comentario: p.comentario,
      respondidoEm: iso(p.respondido_em),
      enviadoEm: iso(p.enviado_em),
      // Link para compartilhar no WhatsApp ou copiar.
      link: linkConvite(p.id),
    })),
  };
}

// ---------------------------------------------------------------------------
// Envio dos e-mails
// ---------------------------------------------------------------------------

interface ResultadoEnvio {
  emailConfigurado: boolean;
  enviados: number;
  semEmail: number;
  bloqueados: number;
  falhas: number;
}

async function enviarAosParticipantes(
  r: ReuniaoRow,
  ps: ParticipanteRow[],
  tipo: TipoEmail,
  organizador: string,
  log: FastifyBaseLogger,
): Promise<ResultadoEnvio> {
  const saida: ResultadoEnvio = {
    emailConfigurado: emailConfigurado(),
    enviados: 0,
    semEmail: 0,
    bloqueados: 0,
    falhas: 0,
  };
  const marcar = db.prepare('UPDATE convite_participantes SET enviado_em = ? WHERE id = ?');
  const bloqueado = db.prepare('SELECT 1 FROM email_bloqueados WHERE email = ?');

  await Promise.all(
    ps.map(async (p) => {
      if (!p.email) {
        saida.semEmail++;
        return;
      }
      if (!saida.emailConfigurado) return;
      if (bloqueado.get(p.email)) {
        saida.bloqueados++;
        return;
      }
      const link = linkConvite(p.id);
      const msg = montarEmail({
        tipo,
        titulo: r.titulo,
        inicio: r.inicio,
        fuso: r.fuso,
        local: r.local,
        descricao: r.descricao,
        organizador,
        nomeConvidado: p.nome,
        link,
      });
      try {
        await enviarEmail({
          para: p.email,
          assunto: msg.assunto,
          html: msg.html,
          texto: msg.texto,
          responderPara: organizador,
          cabecalhos: {
            'List-Unsubscribe': `<${link}/parar>`,
            'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
          },
        });
        marcar.run(Date.now(), p.id);
        saida.enviados++;
      } catch (e) {
        saida.falhas++;
        log.warn({ err: e, participante: p.id }, 'falha ao enviar e-mail de convite');
      }
    }),
  );
  return saida;
}

// ---------------------------------------------------------------------------
// Rotas
// ---------------------------------------------------------------------------

export async function rotasConvites(app: FastifyInstance) {
  const auth = { preHandler: [app.autenticar] };
  const comLimite = { preHandler: [app.autenticar], config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };

  // Cria a reunião, grava os convidados e envia os e-mails.
  app.post('/convites', comLimite, async (req, reply) => {
    const dados = novaReuniaoEsquema.parse(req.body);
    const usuarioId = req.user.sub;
    const inicio = Date.parse(dados.inicio);
    if (inicio < Date.now() - 5 * 60 * 1000) return reply.code(400).send({ erro: 'inicio_no_passado' });

    // Mesmo e-mail duas vezes vira um convidado só.
    const vistos = new Set<string>();
    const convidados = dados.participantes.filter((p) => {
      if (!p.email) return true;
      if (vistos.has(p.email)) return false;
      vistos.add(p.email);
      return true;
    });

    // Teto diário de convidados por usuário (controle de custo e contra uso indevido).
    const { qtd } = db
      .prepare(
        `SELECT COUNT(*) AS qtd FROM convite_participantes p
         JOIN convite_reunioes r ON r.id = p.reuniao_id
         WHERE r.usuario_id = ? AND p.criado_em >= ?`,
      )
      .get(usuarioId, Date.now() - UM_DIA) as unknown as { qtd: number };
    if (qtd + convidados.length > config.LIMITE_CONVITES_DIARIO) {
      return reply.code(429).send({ erro: 'limite_diario_convites' });
    }

    const agora = Date.now();
    const reuniaoId = randomUUID();
    transacao(() => {
      db.prepare(
        `INSERT INTO convite_reunioes (id, usuario_id, titulo, inicio, fuso, local, descricao, status, criado_em, atualizado_em)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'ativa', ?, ?)`,
      ).run(reuniaoId, usuarioId, dados.titulo, inicio, dados.fuso, dados.local ?? null, dados.descricao ?? null, agora, agora);
      const inserir = db.prepare(
        `INSERT INTO convite_participantes (id, reuniao_id, nome, email, telefone, resposta, criado_em)
         VALUES (?, ?, ?, ?, ?, 'pendente', ?)`,
      );
      for (const p of convidados) inserir.run(randomUUID(), reuniaoId, p.nome, p.email ?? null, p.telefone ?? null, agora);
    });

    const reuniao = buscarReuniao(reuniaoId, usuarioId)!;
    const envio = await enviarAosParticipantes(
      reuniao,
      participantesDe(reuniaoId),
      'convite',
      emailDoUsuario(usuarioId),
      req.log,
    );
    // Avisa o Make sem esperar a resposta dele.
    void sendToMake('meeting.created', paraMake(reuniao, participantesDe(reuniaoId)));
    return reply.code(201).send({ ...serializar(reuniao, participantesDe(reuniaoId)), envio });
  });

  // Reuniões dos últimos 30 dias em diante, da mais próxima para a mais distante.
  app.get('/convites', auth, async (req) => {
    const usuarioId = req.user.sub;
    const desde = Date.now() - 30 * UM_DIA;
    const rs = db
      .prepare('SELECT * FROM convite_reunioes WHERE usuario_id = ? AND inicio >= ? ORDER BY inicio ASC')
      .all(usuarioId, desde) as unknown as ReuniaoRow[];
    const ps = db
      .prepare(
        `SELECT p.* FROM convite_participantes p
         JOIN convite_reunioes r ON r.id = p.reuniao_id
         WHERE r.usuario_id = ? AND r.inicio >= ?
         ORDER BY p.criado_em ASC, p.nome ASC`,
      )
      .all(usuarioId, desde) as unknown as ParticipanteRow[];

    const porReuniao = new Map<string, ParticipanteRow[]>();
    for (const p of ps) {
      const lista = porReuniao.get(p.reuniao_id) ?? [];
      lista.push(p);
      porReuniao.set(p.reuniao_id, lista);
    }
    return { reunioes: rs.map((r) => serializar(r, porReuniao.get(r.id) ?? [])) };
  });

  app.get('/convites/:id', auth, async (req, reply) => {
    const { id } = idEsquema.parse(req.params);
    const r = buscarReuniao(id, req.user.sub);
    if (!r) return reply.code(404).send({ erro: 'nao_encontrada' });
    return serializar(r, participantesDe(id));
  });

  // Edita. Mudou o horário? As respostas voltam para "aguardando" e todos recebem o aviso.
  app.patch('/convites/:id', comLimite, async (req, reply) => {
    const { id } = idEsquema.parse(req.params);
    const usuarioId = req.user.sub;
    const edicao = edicaoEsquema.parse(req.body);
    const r = buscarReuniao(id, usuarioId);
    if (!r) return reply.code(404).send({ erro: 'nao_encontrada' });
    if (r.status === 'cancelada') return reply.code(409).send({ erro: 'reuniao_cancelada' });

    const novoInicio = edicao.inicio !== undefined ? Date.parse(edicao.inicio) : r.inicio;
    const inicioMudou = novoInicio !== r.inicio;
    const agora = Date.now();

    transacao(() => {
      db.prepare(
        'UPDATE convite_reunioes SET titulo = ?, inicio = ?, fuso = ?, local = ?, descricao = ?, atualizado_em = ? WHERE id = ?',
      ).run(
        edicao.titulo ?? r.titulo,
        novoInicio,
        edicao.fuso ?? r.fuso,
        edicao.local !== undefined ? edicao.local : r.local,
        edicao.descricao !== undefined ? edicao.descricao : r.descricao,
        agora,
        id,
      );
      if (inicioMudou) {
        db.prepare(
          "UPDATE convite_participantes SET resposta = 'pendente', comentario = NULL, respondido_em = NULL WHERE reuniao_id = ?",
        ).run(id);
      }
    });

    const atualizada = buscarReuniao(id, usuarioId)!;
    const envio = await enviarAosParticipantes(atualizada, participantesDe(id), 'atualizacao', emailDoUsuario(usuarioId), req.log);
    void sendToMake('meeting.updated', { ...paraMake(atualizada, participantesDe(id)), inicioMudou });
    return { ...serializar(atualizada, participantesDe(id)), envio };
  });

  // Cancela e avisa os convidados.
  app.delete('/convites/:id', comLimite, async (req, reply) => {
    const { id } = idEsquema.parse(req.params);
    const usuarioId = req.user.sub;
    const r = buscarReuniao(id, usuarioId);
    if (!r) return reply.code(404).send({ erro: 'nao_encontrada' });
    if (r.status === 'cancelada') return reply.code(409).send({ erro: 'reuniao_cancelada' });

    db.prepare("UPDATE convite_reunioes SET status = 'cancelada', atualizado_em = ? WHERE id = ?").run(Date.now(), id);
    const cancelada = buscarReuniao(id, usuarioId)!;
    const envio = await enviarAosParticipantes(cancelada, participantesDe(id), 'cancelamento', emailDoUsuario(usuarioId), req.log);
    void sendToMake('meeting.cancelled', paraMake(cancelada, participantesDe(id)));
    return { ...serializar(cancelada, participantesDe(id)), envio };
  });

  // Reenvia o convite: para um participante (participanteId) ou para todos que ainda não responderam.
  // Cada pessoa recebe no máximo 1 reenvio a cada 10 minutos.
  app.post('/convites/:id/reenviar', comLimite, async (req, reply) => {
    const { id } = idEsquema.parse(req.params);
    const usuarioId = req.user.sub;
    const { participanteId } = z.object({ participanteId: z.string().uuid().optional() }).parse(req.body ?? {});
    const r = buscarReuniao(id, usuarioId);
    if (!r) return reply.code(404).send({ erro: 'nao_encontrada' });
    if (r.status === 'cancelada') return reply.code(409).send({ erro: 'reuniao_cancelada' });
    if (r.inicio < Date.now()) return reply.code(409).send({ erro: 'reuniao_encerrada' });

    const todos = participantesDe(id);
    const alvo = participanteId ? todos.filter((p) => p.id === participanteId) : todos.filter((p) => p.resposta === 'pendente');
    if (participanteId && alvo.length === 0) return reply.code(404).send({ erro: 'participante_nao_encontrado' });

    const agora = Date.now();
    const recentes = alvo.filter((p) => p.enviado_em !== null && agora - p.enviado_em < INTERVALO_REENVIO);
    const enviaveis = alvo.filter((p) => !recentes.includes(p));
    const envio = await enviarAosParticipantes(r, enviaveis, 'convite', emailDoUsuario(usuarioId), req.log);
    return { envio, ignoradosPorIntervalo: recentes.length };
  });

  // Inclui convidados numa reunião que já existe e manda o convite só para os novos.
  // Quem já está na reunião (mesmo e-mail ou mesmo telefone) é ignorado.
  app.post('/convites/:id/participantes', comLimite, async (req, reply) => {
    const { id } = idEsquema.parse(req.params);
    const usuarioId = req.user.sub;
    const dados = z.object({ participantes: z.array(participanteEsquema).min(1).max(50) }).parse(req.body);
    const r = buscarReuniao(id, usuarioId);
    if (!r) return reply.code(404).send({ erro: 'nao_encontrada' });
    if (r.status === 'cancelada') return reply.code(409).send({ erro: 'reuniao_cancelada' });
    if (r.inicio < Date.now()) return reply.code(409).send({ erro: 'reuniao_encerrada' });

    const atuais = participantesDe(id);
    const emails = new Set<string>(atuais.flatMap((p) => (p.email ? [p.email] : [])));
    const telefones = new Set<string>(atuais.flatMap((p) => (p.telefone ? [p.telefone] : [])));
    const novos = dados.participantes.filter((p) => {
      if (p.email) {
        if (emails.has(p.email)) return false;
        emails.add(p.email);
      }
      if (p.telefone) {
        if (!p.email && telefones.has(p.telefone)) return false;
        telefones.add(p.telefone);
      }
      return true;
    });

    if (novos.length === 0) {
      return {
        ...serializar(r, atuais),
        adicionados: 0,
        envio: { emailConfigurado: emailConfigurado(), enviados: 0, semEmail: 0, bloqueados: 0, falhas: 0 },
      };
    }
    if (atuais.length + novos.length > 50) return reply.code(400).send({ erro: 'limite_participantes' });

    const { qtd } = db
      .prepare(
        `SELECT COUNT(*) AS qtd FROM convite_participantes p
         JOIN convite_reunioes r ON r.id = p.reuniao_id
         WHERE r.usuario_id = ? AND p.criado_em >= ?`,
      )
      .get(usuarioId, Date.now() - UM_DIA) as unknown as { qtd: number };
    if (qtd + novos.length > config.LIMITE_CONVITES_DIARIO) {
      return reply.code(429).send({ erro: 'limite_diario_convites' });
    }

    const agora = Date.now();
    const novosComId = novos.map((p) => ({ ...p, pid: randomUUID() }));
    transacao(() => {
      const inserir = db.prepare(
        `INSERT INTO convite_participantes (id, reuniao_id, nome, email, telefone, resposta, criado_em)
         VALUES (?, ?, ?, ?, ?, 'pendente', ?)`,
      );
      for (const p of novosComId) inserir.run(p.pid, id, p.nome, p.email ?? null, p.telefone ?? null, agora);
    });

    // O e-mail sai só para quem acabou de entrar.
    const idsNovos = new Set<string>(novosComId.map((p) => p.pid));
    const envio = await enviarAosParticipantes(
      r,
      participantesDe(id).filter((p) => idsNovos.has(p.id)),
      'convite',
      emailDoUsuario(usuarioId),
      req.log,
    );
    const finais = participantesDe(id);
    void sendToMake('meeting.updated', { ...paraMake(r, finais), inicioMudou: false, adicionados: novosComId.length });
    return reply.code(201).send({ ...serializar(r, finais), adicionados: novosComId.length, envio });
  });

  // -------------------------------------------------------------------------
  // Aparelhos (push)
  // -------------------------------------------------------------------------

  app.post('/dispositivos', auth, async (req, reply) => {
    const { token, plataforma } = z
      .object({ token: z.string().min(20).max(4096), plataforma: z.enum(['android', 'ios', 'web']).default('android') })
      .parse(req.body);
    // Se o mesmo aparelho trocar de conta, o token passa para a conta nova.
    db.prepare(
      `INSERT INTO dispositivos (token, usuario_id, plataforma, atualizado_em) VALUES (?, ?, ?, ?)
       ON CONFLICT(token) DO UPDATE SET usuario_id = excluded.usuario_id, plataforma = excluded.plataforma, atualizado_em = excluded.atualizado_em`,
    ).run(token, req.user.sub, plataforma, Date.now());
    return reply.code(204).send();
  });

  // Chamar ao sair da conta, para o aparelho parar de receber avisos dela.
  app.post('/dispositivos/remover', auth, async (req, reply) => {
    const { token } = z.object({ token: z.string().min(20).max(4096) }).parse(req.body);
    db.prepare('DELETE FROM dispositivos WHERE token = ? AND usuario_id = ?').run(token, req.user.sub);
    return reply.code(204).send();
  });

  // -------------------------------------------------------------------------
  // Central de avisos
  // -------------------------------------------------------------------------

  app.get('/avisos', auth, async (req) => {
    const { limite } = z.object({ limite: z.coerce.number().int().min(1).max(100).default(50) }).parse(req.query);
    const usuarioId = req.user.sub;
    const linhas = db
      .prepare('SELECT * FROM avisos WHERE usuario_id = ? ORDER BY criado_em DESC LIMIT ?')
      .all(usuarioId, limite) as unknown as {
      id: string;
      reuniao_id: string | null;
      tipo: string;
      titulo: string;
      corpo: string;
      criado_em: number;
      lido_em: number | null;
    }[];
    const { n } = db
      .prepare('SELECT COUNT(*) AS n FROM avisos WHERE usuario_id = ? AND lido_em IS NULL')
      .get(usuarioId) as unknown as { n: number };
    return {
      naoLidos: n,
      avisos: linhas.map((a) => ({
        id: a.id,
        reuniaoId: a.reuniao_id,
        tipo: a.tipo,
        titulo: a.titulo,
        corpo: a.corpo,
        criadoEm: iso(a.criado_em),
        lido: a.lido_em !== null,
      })),
    };
  });

  // Marca como lidos os ids enviados; sem "ids", marca todos.
  app.post('/avisos/lidos', auth, async (req, reply) => {
    const { ids } = z.object({ ids: z.array(z.string().uuid()).max(100).optional() }).parse(req.body ?? {});
    const usuarioId = req.user.sub;
    const agora = Date.now();
    if (ids && ids.length > 0) {
      const marcas = ids.map(() => '?').join(',');
      db.prepare(`UPDATE avisos SET lido_em = ? WHERE usuario_id = ? AND lido_em IS NULL AND id IN (${marcas})`).run(
        agora,
        usuarioId,
        ...ids,
      );
    } else {
      db.prepare('UPDATE avisos SET lido_em = ? WHERE usuario_id = ? AND lido_em IS NULL').run(agora, usuarioId);
    }
    return reply.code(204).send();
  });

  // Diagnóstico simples: o app mostra se o e-mail e o push do servidor estão ligados.
  app.get('/convites-status', auth, async () => ({ email: emailConfigurado(), push: pushConfigurado() }));
}