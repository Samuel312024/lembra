import { config } from './config.js';

export class IaIndisponivel extends Error {
  constructor() {
    super('ANTHROPIC_API_KEY não configurada');
  }
}

/** Chama a API de mensagens da Anthropic. A chave nunca sai do servidor. */
export async function chamarLLM(system: string, usuario: string, maxTokens = 1000): Promise<string> {
  if (!config.ANTHROPIC_API_KEY) throw new IaIndisponivel();

  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': config.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: config.ANTHROPIC_MODEL,
      max_tokens: maxTokens,
      system,
      messages: [{ role: 'user', content: usuario }],
    }),
    signal: AbortSignal.timeout(8000),
  });
  if (!r.ok) throw new Error(`Falha na API de IA (HTTP ${r.status})`);

  const dados = (await r.json()) as { content: { type: string; text?: string }[] };
  return dados.content
    .filter((b) => b.type === 'text')
    .map((b) => b.text ?? '')
    .join('');
}

/** Extrai o JSON da resposta, mesmo que venha com cercas de markdown ou texto em volta. */
export function extrairJson(texto: string): unknown {
  const limpo = texto.replace(/```(?:json)?/gi, '').trim();
  const iniArr = limpo.indexOf('[');
  const iniObj = limpo.indexOf('{');
  const ini = iniArr === -1 ? iniObj : iniObj === -1 ? iniArr : Math.min(iniArr, iniObj);
  const fim = Math.max(limpo.lastIndexOf(']'), limpo.lastIndexOf('}'));
  if (ini === -1 || fim <= ini) throw new Error('Resposta da IA sem JSON');
  return JSON.parse(limpo.slice(ini, fim + 1));
}
