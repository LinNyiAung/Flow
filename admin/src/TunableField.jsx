import { AlertCircle, AlertTriangle, RotateCcw } from 'lucide-react';
import { field } from './appControlShared';
import { CURRENCIES, allowedText, formatValue, timeOptions } from './tunablesShared';

/** One setting: label, note, input by kind, default / allowed text, and "Use default". */
const TunableField = ({ setting: s, draft, onChange, disabled, error, serverNow, changed, canReset, onUseDefault }) => {
  const id = `tunable-${s.key}`;
  const invalid = !!error;
  const cls = `${field} ${invalid ? 'border-red-500/60' : ''}`;

  let input;
  if (s.kind === 'amounts') {
    input = (
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {CURRENCIES.map((c) => (
          <div key={c} className="min-w-0">
            <label htmlFor={`${id}-${c}`} className="block text-[11px] font-semibold text-slate-400 mb-1">{c.toUpperCase()}</label>
            <input id={`${id}-${c}`} type="number" inputMode="decimal" min={0} step="any" value={draft[c]} disabled={disabled}
              aria-invalid={invalid} onChange={(e) => onChange({ ...draft, [c]: e.target.value })} className={cls} />
          </div>
        ))}
      </div>
    );
  } else if (s.kind === 'time') {
    input = (
      <select id={id} value={draft} disabled={disabled} aria-invalid={invalid}
        onChange={(e) => onChange(e.target.value)} className={`${cls} md:max-w-[12rem]`}>
        {timeOptions(s).map((t) => <option key={t} value={t}>{t}</option>)}
      </select>
    );
  } else if (s.kind === 'day_list') {
    input = (
      <input id={id} type="text" inputMode="numeric" placeholder="14, 7, 3, 1" value={draft} disabled={disabled}
        aria-invalid={invalid} onChange={(e) => onChange(e.target.value)} className={`${cls} md:max-w-xs`} />
    );
  } else {
    input = (
      <input id={id} type="number" inputMode="decimal" min={s.min} max={s.max} step={s.kind === 'number' ? 0.1 : 1}
        value={draft} disabled={disabled} aria-invalid={invalid}
        onChange={(e) => onChange(e.target.value)} className={`${cls} md:max-w-[12rem]`} />
    );
  }

  return (
    <div className="p-4 border-b border-white/5 last:border-b-0">
      <div className="flex items-center gap-2 mb-1 flex-wrap">
        <label htmlFor={s.kind === 'amounts' ? `${id}-mmk` : id} className="text-sm font-bold text-slate-100">{s.label}</label>
        {changed && <span className="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded bg-blue-500/15 text-blue-300">Changed</span>}
      </div>
      {s.note && <div className="text-xs text-slate-400 mb-3">{s.note}</div>}
      {!s.note && <div className="mb-2" />}
      {input}
      <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-slate-500">
        <span><span className="font-semibold text-slate-400">Default: </span>{formatValue(s, s.default)}</span>
        <span><span className="font-semibold text-slate-400">Allowed: </span>{allowedText(s)}</span>
        {canReset && (
          <button type="button" onClick={onUseDefault}
            className="px-2.5 py-1 bg-slate-500/20 border border-slate-500/30 hover:bg-slate-500/30 rounded-lg text-slate-300 font-semibold flex items-center gap-1.5">
            <RotateCcw size={12} /> Use default
          </button>
        )}
      </div>
      {serverNow && (
        <div className="mt-2 flex items-start gap-1.5 text-xs text-amber-300">
          <AlertTriangle size={14} className="flex-shrink-0 mt-px" />
          <span className="min-w-0 break-words">On the server now: {serverNow}</span>
        </div>
      )}
      {error && (
        <div role="alert" className="mt-2 flex items-start gap-1.5 text-xs text-red-300">
          <AlertCircle size={14} className="flex-shrink-0 mt-px" />
          <span className="min-w-0 break-words">{error}</span>
        </div>
      )}
    </div>
  );
};

export default TunableField;
