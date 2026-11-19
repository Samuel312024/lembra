import nodemailer from 'nodemailer';
import { config } from '../config.js';

type Transporte = ReturnType<typeof nodemailer.createTransport>;

let transporte: Transporte | null | undefined;

function obter(): Transporte | null {
  if (transporte !== undefined) return transporte;
  if (!config.SMTP_HOST) {
    transporte = null;
    return null;
  }
  transporte = nodemailer.createTransport({
    host: config.SMTP_HOST,
    port: config.SMTP_PORT,
    secure: config.SMTP_PORT === 465,
    auth: config.SMTP_USER ? { user: config.SMTP_USER, pass: config.SMTP_PASS ?? '' } : undefined,
  });
  return transporte;
}

export const emailConfigurado = () => obter() !== null;

export interface Mensagem {
  para: string;
  assunto: string;
  html: string;
  texto: string;
  responderPara?: string;
  cabecalhos?: Record<string, string>;
}

/** true = enviado; false = SMTP não configurado; lança erro se o servidor de e-mail recusar. */
export async function enviarEmail(m: Mensagem): Promise<boolean> {
  const t = obter();
  if (!t) return false;
  await t.sendMail({
    from: config.EMAIL_DE,
    to: m.para,
    replyTo: m.responderPara,
    subject: m.assunto,
    html: m.html,
    text: m.texto,
    headers: m.cabecalhos,
  });
  return true;
}