// Helpers for the "Numbers & times" tab: turning a setting's value into what a form box holds and back.
// A "draft" is the raw form state of one setting: a string, or {mmk, usd, thb} strings for amounts.

export const CURRENCIES = ['mmk', 'usd', 'thb'];

const sameValue = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export { sameValue };

export const toDraft = (s, value) => {
  if (s.kind === 'day_list') return value.join(', ');
  if (s.kind === 'amounts') return Object.fromEntries(CURRENCIES.map((c) => [c, String(value[c])]));
  return String(value);
};

const toNumber = (text) => {
  const t = String(text).trim();
  if (!t) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
};

/** The JSON value of a draft: { value } or { error } (a message for text the person left unreadable). */
export const parseDraft = (s, draft) => {
  if (s.kind === 'days') {
    const t = String(draft).trim();
    return /^\d+$/.test(t) ? { value: Number(t) } : { error: 'Enter a whole number of days' };
  }
  if (s.kind === 'day_list') {
    const parts = String(draft).split(/[\s,]+/).filter(Boolean);
    if (parts.length === 0) return { error: 'Enter the days, like 14, 7, 3, 1' };
    if (!parts.every((p) => /^\d+$/.test(p))) return { error: 'Use whole numbers separated by commas, like 14, 7, 3, 1' };
    return { value: parts.map(Number).sort((a, b) => b - a) };
  }
  if (s.kind === 'number') {
    const n = toNumber(draft);
    return n === null ? { error: 'Enter a number' } : { value: n };
  }
  if (s.kind === 'amounts') {
    const out = {};
    for (const c of CURRENCIES) {
      const n = toNumber(draft[c]);
      if (n === null) return { error: `Enter a number for ${c.toUpperCase()}` };
      out[c] = n;
    }
    return { value: out };
  }
  return { value: draft }; // time: picked from a list
};

const num = (n) => Number(n).toLocaleString('en-US');

/** A value as readable text. */
export const formatValue = (s, value) => {
  if (s.kind === 'day_list') return value.join(', ');
  if (s.kind === 'amounts') return CURRENCIES.map((c) => `${c.toUpperCase()} ${num(value[c])}`).join(' / ');
  if (s.kind === 'days') return `${value} ${value === 1 ? 'day' : 'days'}`;
  return String(value);
};

/** The allowed range as readable text. */
export const allowedText = (s) => {
  if (s.kind === 'days') return `Whole days, ${s.min} to ${s.max}`;
  if (s.kind === 'day_list') return `1 to 4 different whole days, each ${s.min} to ${s.max}`;
  if (s.kind === 'number') return `${s.min} to ${s.max}`;
  if (s.kind === 'amounts') return `Above 0, at most ${CURRENCIES.map((c) => `${c.toUpperCase()} ${num(s.max[c])}`).join(' / ')}`;
  return `${s.min} to ${s.max}, in 15-minute steps`;
};

/** "HH:MM" steps of 15 minutes from min to max inclusive. */
export const timeOptions = (s) => {
  const mins = (t) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3));
  const out = [];
  for (let m = mins(s.min); m <= mins(s.max); m += 15) {
    out.push(`${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`);
  }
  return out;
};
