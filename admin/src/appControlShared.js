import { errorMessage, ApiError } from './api';

export const MAX_MESSAGE = 300;
export const card = 'bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5';
export const field = 'w-full min-w-0 px-3 py-2.5 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 disabled:opacity-60 disabled:cursor-not-allowed';

// ─── Helpers ──────────────────────────────────────────────────────────────────
const pad = (n) => String(n).padStart(2, '0');

/** An ISO string with an offset -> the browser-local "YYYY-MM-DDTHH:mm" a datetime-local input wants ('' when none). */
export const isoToLocalInput = (iso) => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

/** A datetime-local value -> an ISO string carrying the browser's offset (like 2026-11-25T14:00:00+06:30); null when empty. */
export const localInputToIso = (value) => {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? '+' : '-';
  const abs = Math.abs(off);
  return `${value.length === 16 ? `${value}:00` : value}${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
};

/** 422 detail (a string, or FastAPI's list) as readable lines. */
export const errorLines = (err) => {
  if (err instanceof ApiError && err.status === 422) {
    const d = err.detail;
    if (typeof d === 'string') return d.split('; ').map((s) => s.trim()).filter(Boolean);
    return [err.message || 'The server refused these values'];
  }
  return [errorMessage(err, 'Request failed')];
};
