import { createHmac, timingSafeEqual } from 'node:crypto';
import { config } from '../config.js';

/**
 * Link de resposta de um participante: "<id do participante>.<assinatura>".
 * O id é um UUID aleatório e a assinatura (HMAC) impede forjar ou adivinhar links.
 * Como o link é derivado do id, dá para reenviá-lo ou compartilhá-lo no WhatsApp
 * quando quiser, sem guardar o token em lugar nenhum.
 */
const segredo = config.CONVITE_SECRET ?? config.JWT_SECRET;

const assinar = (id: string) => createHmac('sha256', segredo).update(`convite:${id}`).digest('base64url');

export const gerarToken = (participanteId: string) => `${participanteId}.${assinar(participanteId)}`;

/** Devolve o id do participante se o token for autêntico; senão, null. */
export function lerToken(token: string): string | null {
  const partes = token.split('.');
  if (partes.length !== 2) return null;
  const [id, assinatura] = partes as [string, string];
  const esperado = Buffer.from(assinar(id));
  const recebido = Buffer.from(assinatura);
  if (esperado.length !== recebido.length || !timingSafeEqual(esperado, recebido)) return null;
  return id;
}

export const urlBase = () => config.PUBLIC_URL.replace(/\/+$/, '');

/** Link público que o convidado abre (e-mail ou WhatsApp). */
export const linkConvite = (participanteId: string) => `${urlBase()}/r/${gerarToken(participanteId)}`;