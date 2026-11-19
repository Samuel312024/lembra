import type { FastifyBaseLogger, FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import { db } from '../db.js';
import { criarAviso } from '../servicos/avisos.js';
import { lerToken } from '../servicos/token.js';
import {
  dataCurta,
  mascarar,
  paginaConvite,
  paginaMensagem,
  paginaParar,
  type Resposta,
} from '../servicos/textos.js';
import { sendToMake } from '../servicos/make.js';

type Linha = {
  participante_id: string;
  nome: string;
  email: string | null;
  resposta: Resposta;
  comentario: string | null;
  reuniao_id: string;
  usuario_id: string;
  titulo: string;
  inicio: number;
  fuso: string;
  local: string | null;
  descricao: string | null;
  status: 'ativa' | 'cancelada';
  organizador: string;
};

const RESPOSTAS = ['aceito', 'recusado', 'talvez'] as const;
const respostaValida = (v: unknown): v is (typeof RESPOSTAS)[number] =>
  typeof v === 'string' && (RESPOSTAS as readonly string[]).includes(v);

/** Acha o convite pelo token do link. Token adulterado ou desconhecido = null. */
function buscar(token: string): Linha | null {
  const id = lerToken(token);
  if (!id) return null;
  const linha = db
    .prepare(
      `SELECT p.id AS participante_id, p.nome, p.email, p.resposta, p.comentario,
              r.id AS reuniao_id, r.usuario_id, r.titulo, r.inicio, r.fuso, r.local, r.descricao, r.status,
              u.email AS organizador
       FROM convite_participantes p
       JOIN convite_reunioes r ON r.id = p.reuniao_id
       JOIN usuarios u ON u.id = r.usuario_id
       WHERE p.id = ?`,
    )
    .get(id) as unknown as Linha | undefined;
  return linha ?? null;
}

const situacao = (l: Linha): 'ativa' | 'cancelada' | 'encerrada' =>
  l.status === 'cancelada' ? 'cancelada' : l.inicio < Date.now() ? 'encerrada' : 'ativa';

/** Envia a página com cabeçalhos que impedem cache, vazamento do link e uso em iframe. */
function enviarPagina(reply: FastifyReply, status: number, html: string) {
  return reply
    .code(status)
    .header('Cache-Control', 'no-store')
    .header('Referrer-Policy', 'no-referrer')
    .header('X-Robots-Tag', 'noindex, nofollow')
    .header('X-Frame-Options', 'DENY')
    .header(
      'Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
    )
    .type('text/html; charset=utf-8')
    .send(html);
}

const naoEncontrado = (reply: FastifyReply) =>
  enviarPagina(
    reply,
    404,
    paginaMensagem('Convite não encontrado', 'Este link não é válido. Peça um novo convite a quem enviou.'),
  );

const plural = (n: number, singular: string, plur: string) => `${n} ${n === 1 ? singular : plur}`;

/** Avisa o organizador (central do app + push). */
function avisarOrganizador(l: Linha, resposta: Resposta, comentario: string | null, eraPendente: boolean, log: FastifyBaseLogger) {
  const titulo =
    resposta === 'aceito'
      ? `${l.nome} aceitou o convite`
      : resposta === 'recusado'
        ? `${l.nome} recusou o convite`
        : `${l.nome} respondeu: talvez`;
  const corpo = `${l.titulo} · ${dataCurta(l.inicio, l.fuso)}${comentario ? ` — “${comentario}”` : ''}`;
  criarAviso(
    {
      usuarioId: l.usuario_id,
      reuniaoId: l.reuniao_id,
      tipo: 'resposta',
      titulo,
      corpo,
      dados: { conviteId: l.participante_id, resposta },
    },
    log,
  );

  // Quando a última pessoa responde, um segundo aviso resume a reunião.
  if (!eraPendente) return;
  const contagem = db
    .prepare('SELECT resposta, COUNT(*) AS n FROM convite_participantes WHERE reuniao_id = ? GROUP BY resposta')
    .all(l.reuniao_id) as unknown as { resposta: Resposta; n: number }[];
  const n = (r: Resposta) => contagem.find((c) => c.resposta === r)?.n ?? 0;
  if (n('pendente') > 0) return;
  const resumo = [
    n('aceito') > 0 ? plural(n('aceito'), 'aceitou', 'aceitaram') : '',
    n('recusado') > 0 ? plural(n('recusado'), 'recusou', 'recusaram') : '',
    n('talvez') > 0 ? `${n('talvez')} talvez` : '',
  ]
    .filter(Boolean)
    .join(', ');
  criarAviso(
    {
      usuarioId: l.usuario_id,
      reuniaoId: l.reuniao_id,
      tipo: 'todos_responderam',
      titulo: 'Todos responderam',
      corpo: `${l.titulo} · ${resumo}`,
    },
    log,
  );

  // Avisa o Make que todos responderam (só chega aqui quando não há mais pendentes).
  void sendToMake('meeting.all_responded', {
    reuniaoId: l.reuniao_id,
    titulo: l.titulo,
    inicio: new Date(l.inicio).toISOString(),
    fuso: l.fuso,
    organizador: l.organizador,
    resumo: { aceito: n('aceito'), recusado: n('recusado'), talvez: n('talvez') },
  });
}

export async function rotasResposta(app: FastifyInstance) {
  // Os formulários das páginas enviam "application/x-www-form-urlencoded".
  // Registrado aqui dentro, vale só para estas rotas.
  app.addContentTypeParser('application/x-www-form-urlencoded', { parseAs: 'string' }, (_req, body, done) => {
    try {
      done(null, Object.fromEntries(new URLSearchParams(body as string)));
    } catch (e) {
      done(e as Error);
    }
  });

  const limite = { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } };

  // Abrir o link NÃO registra nada: só mostra a página. Gmail, antivírus e a prévia do WhatsApp
  // abrem links sozinhos, então a resposta só vale quando a pessoa toca no botão (POST).
  app.get('/r/:token', limite, async (req, reply) => {
    const { token } = req.params as { token: string };
    const { acao, ok } = req.query as { acao?: string; ok?: string };
    const l = buscar(token);
    if (!l) return naoEncontrado(reply);

    return enviarPagina(
      reply,
      200,
      paginaConvite({
        token,
        situacao: situacao(l),
        nome: l.nome,
        organizador: l.organizador,
        titulo: l.titulo,
        inicio: l.inicio,
        fuso: l.fuso,
        local: l.local,
        descricao: l.descricao,
        resposta: l.resposta,
        comentario: l.comentario,
        acaoSugerida: respostaValida(acao) ? acao : null,
        registrado: ok === '1' && l.resposta !== 'pendente',
      }),
    );
  });

  app.post('/r/:token', limite, async (req, reply) => {
    const { token } = req.params as { token: string };
    const l = buscar(token);
    if (!l) return naoEncontrado(reply);

    const corpo = z
      .object({
        resposta: z.enum(RESPOSTAS),
        comentario: z.string().trim().max(300).optional(),
      })
      .safeParse(req.body ?? {});
    if (!corpo.success) {
      return enviarPagina(reply, 400, paginaMensagem('Resposta inválida', 'Volte ao convite e escolha uma das opções.'));
    }

    const sit = situacao(l);
    if (sit !== 'ativa') {
      return enviarPagina(
        reply,
        409,
        paginaMensagem(
          sit === 'cancelada' ? 'Reunião cancelada' : 'Reunião encerrada',
          sit === 'cancelada' ? 'Esta reunião foi cancelada, então não dá mais para responder.' : 'Esta reunião já aconteceu.',
        ),
      );
    }

    const { resposta } = corpo.data;
    const comentario = corpo.data.comentario || null;
    const mudou = l.resposta !== resposta || (l.comentario ?? null) !== comentario;

    // Tocar duas vezes no mesmo botão não gera aviso repetido.
    if (mudou) {
      db.prepare('UPDATE convite_participantes SET resposta = ?, comentario = ?, respondido_em = ? WHERE id = ?').run(
        resposta,
        comentario,
        Date.now(),
        l.participante_id,
      );
      avisarOrganizador(l, resposta, comentario, l.resposta === 'pendente', req.log);
      // Avisa o Make que o convidado respondeu.
      void sendToMake('invite.responded', {
        reuniaoId: l.reuniao_id,
        titulo: l.titulo,
        inicio: new Date(l.inicio).toISOString(),
        fuso: l.fuso,
        participante: l.nome,
        email: l.email,
        resposta,
        comentario,
        organizador: l.organizador,
      });
    }

    // Redireciona para a página (POST → GET) para o F5 não reenviar a resposta.
    return reply
      .code(303)
      .header('Location', `/r/${encodeURIComponent(token)}?ok=1`)
      .header('Cache-Control', 'no-store')
      .send();
  });

  // Pedido para não receber mais convites por e-mail (LGPD).
  app.get('/r/:token/parar', limite, async (req, reply) => {
    const { token } = req.params as { token: string };
    const l = buscar(token);
    if (!l || !l.email) return naoEncontrado(reply);
    return enviarPagina(reply, 200, paginaParar(token, mascarar(l.email)));
  });

  // Também atende o "cancelar inscrição com um toque" do Gmail e do Outlook (POST).
  app.post('/r/:token/parar', limite, async (req, reply) => {
    const { token } = req.params as { token: string };
    const l = buscar(token);
    if (!l || !l.email) return naoEncontrado(reply);
    db.prepare('INSERT OR IGNORE INTO email_bloqueados (email, criado_em) VALUES (?, ?)').run(l.email, Date.now());
    return enviarPagina(
      reply,
      200,
      paginaMensagem('Pronto', 'Você não receberá mais convites do Lembra neste e-mail.'),
    );
  });
}