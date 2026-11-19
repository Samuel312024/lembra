export type Resposta = 'pendente' | 'aceito' | 'recusado' | 'talvez';
export type TipoEmail = 'convite' | 'atualizacao' | 'cancelamento';

export const ROTULO_RESPOSTA: Record<Resposta, string> = {
  pendente: 'Aguardando',
  aceito: 'Aceito',
  recusado: 'Recusado',
  talvez: 'Talvez',
};

// ---------------------------------------------------------------------------
// Utilitários
// ---------------------------------------------------------------------------

/** Escapa texto digitado por alguém antes de colocar em HTML. */
export function esc(texto: string): string {
  return texto
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const maiuscula = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

function partes(ms: number, fuso: string) {
  const d = new Date(ms);
  const f = (o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat('pt-BR', { ...o, timeZone: fuso }).format(d);
  return {
    diaSemanaLongo: f({ weekday: 'long' }),
    diaSemanaCurto: f({ weekday: 'short' }).replace('.', ''),
    dia: f({ day: 'numeric' }),
    mesLongo: f({ month: 'long' }),
    mesCurto: f({ month: 'short' }).replace('.', ''),
    ano: f({ year: 'numeric' }),
    hora: f({ hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }),
  };
}

/** "Quinta-feira, 20 de novembro de 2026 às 14:00" */
export function dataLonga(ms: number, fuso: string): string {
  const p = partes(ms, fuso);
  return `${maiuscula(p.diaSemanaLongo)}, ${p.dia} de ${p.mesLongo} de ${p.ano} às ${p.hora}`;
}

/** "qui, 20 nov · 14:00" */
export function dataCurta(ms: number, fuso: string): string {
  const p = partes(ms, fuso);
  return `${p.diaSemanaCurto}, ${p.dia} ${p.mesCurto} · ${p.hora}`;
}

/** Só aceita http(s). Qualquer outra coisa (inclusive "javascript:") vira texto simples. */
function urlSegura(texto: string): string | null {
  try {
    const u = new URL(texto);
    return u.protocol === 'https:' || u.protocol === 'http:' ? u.toString() : null;
  } catch {
    return null;
  }
}

function localHtml(local: string): string {
  const url = urlSegura(local);
  return url ? `<a href="${esc(url)}">${esc(local)}</a>` : esc(local);
}

const quebras = (s: string) => esc(s).replace(/\r?\n/g, '<br>');

/** Nome do fuso para mostrar ao convidado ("Brasília" em vez de "America/Sao_Paulo"). */
export function nomeFuso(fuso: string): string {
  return fuso === 'America/Sao_Paulo' ? 'Brasília' : fuso.replace(/_/g, ' ');
}

export function mascarar(email: string): string {
  const [usuario = '', dominio = ''] = email.split('@');
  return `${usuario.slice(0, 1)}***@${dominio}`;
}

// ---------------------------------------------------------------------------
// E-mail do convite
// ---------------------------------------------------------------------------

export interface DadosEmail {
  tipo: TipoEmail;
  titulo: string;
  inicio: number;
  fuso: string;
  local: string | null;
  descricao: string | null;
  organizador: string;
  nomeConvidado: string;
  /** Link único de resposta do convidado. */
  link: string;
}

export function montarEmail(d: DadosEmail): { assunto: string; html: string; texto: string } {
  const quando = dataLonga(d.inicio, d.fuso);
  const cancelada = d.tipo === 'cancelamento';

  const assunto = cancelada
    ? `Cancelada: ${d.titulo}`
    : d.tipo === 'atualizacao'
      ? `Atualizada: ${d.titulo} · ${dataCurta(d.inicio, d.fuso)}`
      : `Convite: ${d.titulo} · ${dataCurta(d.inicio, d.fuso)}`;

  const abertura = cancelada
    ? `<strong>${esc(d.organizador)}</strong> cancelou esta reunião.`
    : d.tipo === 'atualizacao'
      ? `<strong>${esc(d.organizador)}</strong> alterou esta reunião. Confirme de novo se continua valendo para você.`
      : `<strong>${esc(d.organizador)}</strong> convidou você para uma reunião.`;

  const botao = (acao: string, rotulo: string, cor: string, preenchido: boolean) =>
    `<a href="${esc(d.link)}?acao=${acao}" style="display:inline-block;margin:0 8px 10px 0;padding:12px 22px;border-radius:999px;` +
    `border:2px solid ${cor};background:${preenchido ? cor : '#ffffff'};color:${preenchido ? '#ffffff' : cor};` +
    `font-weight:700;font-size:15px;text-decoration:none">${rotulo}</a>`;

  const linhaLocal = d.local
    ? `<p style="margin:0 0 6px;font-size:15px;color:#4a453f"><strong>Onde:</strong> ${localHtml(d.local)}</p>`
    : '';
  const linhaDescricao = d.descricao
    ? `<p style="margin:14px 0 0;font-size:15px;color:#4a453f">${quebras(d.descricao)}</p>`
    : '';

  const botoes = cancelada
    ? ''
    : `<p style="margin:22px 0 4px;font-size:14px;color:#6b655e">Você vai?</p>
       <div>${botao('aceito', 'Aceitar', '#1f9d55', true)}${botao('talvez', 'Talvez', '#c58a12', false)}${botao('recusado', 'Recusar', '#d64545', false)}</div>
       <p style="margin:6px 0 0;font-size:12px;color:#8a847c">Ao tocar, você confirma a resposta numa página segura do Lembra.</p>`;

  const html = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f4f1ec;font-family:-apple-system,'Segoe UI',Roboto,Arial,sans-serif">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f1ec"><tr><td align="center" style="padding:24px 12px">
  <table role="presentation" width="520" cellspacing="0" cellpadding="0" style="max-width:520px;width:100%;background:#ffffff;border-radius:20px;border:1px solid #e4ded5">
    <tr><td style="padding:22px 26px 0;font-size:18px;font-weight:800;color:#e8772e">Lembra</td></tr>
    <tr><td style="padding:14px 26px 26px;color:#1d1b19">
      <p style="margin:0 0 6px;font-size:15px;color:#4a453f">Olá, ${esc(d.nomeConvidado)}.</p>
      <p style="margin:0 0 18px;font-size:15px;color:#4a453f">${abertura}</p>
      <h1 style="margin:0 0 14px;font-size:22px;line-height:1.25;${cancelada ? 'text-decoration:line-through;' : ''}">${esc(d.titulo)}</h1>
      <div style="padding:14px 16px;border-radius:14px;background:#fdf1e8;margin:0 0 14px">
        <p style="margin:0;font-size:16px;font-weight:700">${esc(quando)}</p>
        <p style="margin:2px 0 0;font-size:12px;color:#8a847c">Horário de ${esc(nomeFuso(d.fuso))}</p>
      </div>
      ${linhaLocal}${linhaDescricao}${botoes}
    </td></tr>
  </table>
  <p style="max-width:520px;margin:14px 0 0;font-size:12px;line-height:1.5;color:#8a847c">
    Este e-mail foi enviado por ${esc(d.organizador)} usando o Lembra. Se você não esperava este convite, pode ignorá-lo.
    <a href="${esc(d.link)}/parar" style="color:#8a847c">Não quero receber convites do Lembra</a>.
  </p>
</td></tr></table>
</body></html>`;

  const texto = [
    `Olá, ${d.nomeConvidado}.`,
    cancelada
      ? `${d.organizador} cancelou esta reunião.`
      : d.tipo === 'atualizacao'
        ? `${d.organizador} alterou esta reunião. Confirme de novo se continua valendo para você.`
        : `${d.organizador} convidou você para uma reunião.`,
    '',
    d.titulo,
    quando,
    d.local ? `Onde: ${d.local}` : '',
    d.descricao ?? '',
    '',
    cancelada ? '' : `Responder (aceitar, talvez ou recusar): ${d.link}`,
    '',
    `Não quero receber convites do Lembra: ${d.link}/parar`,
  ]
    .filter((l, i, a) => l !== '' || a[i - 1] !== '')
    .join('\n');

  return { assunto, html, texto };
}

// ---------------------------------------------------------------------------
// Páginas web (o convidado não precisa instalar nada)
// ---------------------------------------------------------------------------

const ESTILO = `
:root{color-scheme:light dark;--bg:#f4f1ec;--card:#fff;--txt:#1d1b19;--suave:#6b655e;--borda:#e4ded5;--marca:#e8772e;--ok:#1f9d55;--erro:#d64545;--aviso:#c58a12;--destaque:rgba(232,119,46,.12)}
@media (prefers-color-scheme:dark){:root{--bg:#121513;--card:#1b201d;--txt:#f2efe9;--suave:#a19b92;--borda:#2b312d;--destaque:rgba(232,119,46,.16)}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--txt);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;display:flex;justify-content:center;padding:20px 14px;min-height:100vh}
main{width:100%;max-width:480px}
.marca{font-weight:800;color:var(--marca);margin:6px 4px 14px;font-size:18px}
.card{background:var(--card);border:1px solid var(--borda);border-radius:20px;padding:22px}
h1{font-size:22px;line-height:1.25;margin:4px 0 8px}
p{margin:0 0 10px}
.suave{color:var(--suave);font-size:14px}
.quando{margin:16px 0;padding:14px 16px;border-radius:14px;background:var(--destaque)}
.quando strong{display:block;font-size:17px}
.faixa{margin:0 0 14px;padding:11px 14px;border-radius:12px;font-size:15px;border:1px solid var(--borda)}
.faixa.ok{border-color:var(--ok);color:var(--ok)}
.faixa.erro{border-color:var(--erro);color:var(--erro)}
label{display:block;font-size:14px;color:var(--suave);margin:16px 0 6px}
textarea{width:100%;min-height:76px;border-radius:12px;border:1px solid var(--borda);background:transparent;color:inherit;padding:10px 12px;font:inherit;resize:vertical}
.botoes{display:grid;gap:10px;margin-top:14px}
button{font:inherit;font-weight:700;border-radius:999px;padding:13px 18px;cursor:pointer;border:2px solid var(--cor,var(--marca));background:transparent;color:var(--cor,var(--marca))}
button.forte{background:var(--cor,var(--marca));color:#fff}
.aceito{--cor:var(--ok)}.recusado{--cor:var(--erro)}.talvez{--cor:var(--aviso)}
a{color:var(--marca)}
.rodape{margin:14px 4px 0;font-size:12px;color:var(--suave)}
`;

function layout(titulo: string, conteudo: string, rodape = ''): string {
  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>${esc(titulo)}</title><style>${ESTILO}</style></head>
<body><main><div class="marca">Lembra</div><div class="card">${conteudo}</div>${rodape ? `<p class="rodape">${rodape}</p>` : ''}</main></body></html>`;
}

export function paginaMensagem(titulo: string, texto: string): string {
  return layout(titulo, `<h1>${esc(titulo)}</h1><p>${esc(texto)}</p>`);
}

export interface DadosPagina {
  token: string;
  situacao: 'ativa' | 'cancelada' | 'encerrada';
  nome: string;
  organizador: string;
  titulo: string;
  inicio: number;
  fuso: string;
  local: string | null;
  descricao: string | null;
  resposta: Resposta;
  comentario: string | null;
  acaoSugerida: Resposta | null;
  /** Mostra o aviso verde de "resposta registrada". */
  registrado: boolean;
}

export function paginaConvite(d: DadosPagina): string {
  const quando = `<div class="quando"><strong>${esc(dataLonga(d.inicio, d.fuso))}</strong><span class="suave">Horário de ${esc(
    nomeFuso(d.fuso),
  )}</span></div>`;
  const onde = d.local ? `<p><strong>Onde:</strong> ${localHtml(d.local)}</p>` : '';
  const sobre = d.descricao ? `<p class="suave">${quebras(d.descricao)}</p>` : '';

  const faixas: string[] = [];
  if (d.registrado) {
    faixas.push(
      `<div class="faixa ok">Resposta registrada: <strong>${esc(ROTULO_RESPOSTA[d.resposta])}</strong>. ${esc(
        d.organizador,
      )} já foi avisado(a).</div>`,
    );
  } else if (d.resposta !== 'pendente') {
    faixas.push(`<div class="faixa">Sua resposta atual: <strong>${esc(ROTULO_RESPOSTA[d.resposta])}</strong></div>`);
  }
  if (d.situacao === 'cancelada') faixas.push('<div class="faixa erro">Esta reunião foi cancelada.</div>');
  if (d.situacao === 'encerrada') faixas.push('<div class="faixa">Esta reunião já aconteceu.</div>');

  let formulario = '';
  if (d.situacao === 'ativa') {
    const forte = d.acaoSugerida ?? (d.resposta !== 'pendente' ? d.resposta : null);
    const b = (r: Exclude<Resposta, 'pendente'>, rotulo: string) =>
      `<button type="submit" name="resposta" value="${r}" class="${r}${forte === r ? ' forte' : ''}">${rotulo}</button>`;
    formulario = `<form method="post" action="/r/${encodeURIComponent(d.token)}">
      <label for="c">Quer deixar um recado? (opcional)</label>
      <textarea id="c" name="comentario" maxlength="300">${esc(d.comentario ?? '')}</textarea>
      <div class="botoes">${b('aceito', 'Aceitar')}${b('talvez', 'Talvez')}${b('recusado', 'Recusar')}</div>
    </form>`;
  }

  return layout(
    d.titulo,
    `<p class="suave">${esc(d.organizador)} convidou ${esc(d.nome)}</p><h1>${esc(d.titulo)}</h1>${quando}${onde}${sobre}${faixas.join('')}${formulario}`,
    `<a href="/r/${encodeURIComponent(d.token)}/parar">Não quero receber convites do Lembra</a>`,
  );
}

export function paginaParar(token: string, emailMascarado: string): string {
  return layout(
    'Parar de receber convites',
    `<h1>Parar de receber convites?</h1>
     <p>Vamos deixar de enviar convites do Lembra para <strong>${esc(emailMascarado)}</strong>.</p>
     <form method="post" action="/r/${encodeURIComponent(token)}/parar"><div class="botoes"><button type="submit" class="forte recusado">Sim, parar de receber</button></div></form>
     <p class="suave" style="margin-top:14px"><a href="/r/${encodeURIComponent(token)}">Voltar ao convite</a></p>`,
  );
}