import { AlertCircle, CheckCircle } from 'lucide-react';

export const ErrorBox = ({ lines }) => (lines?.length > 0 ? (
  <div role="alert" className="mb-6 p-3 bg-red-500/5 border border-red-500/20 rounded-xl text-xs text-red-300 space-y-1">
    {lines.map((e, i) => (
      <div key={i} className="flex items-start gap-1.5 min-w-0">
        <AlertCircle size={14} className="flex-shrink-0 mt-px" />
        <span className="min-w-0 break-words">{e}</span>
      </div>
    ))}
  </div>
) : null);

export const NoticeBox = ({ text }) => (text ? (
  <div className="mb-6 p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-xl text-xs text-emerald-300 flex items-start gap-1.5">
    <CheckCircle size={14} className="flex-shrink-0 mt-px" /> {text}
  </div>
) : null);


// ─── Pieces ───────────────────────────────────────────────────────────────────
export const Counter = ({ value, max }) => (
  <div className={`text-xs mt-1 ${value.length > max ? 'text-red-300' : 'text-slate-500'}`}>{value.length}/{max} characters</div>
);

export const Toggle = ({ checked, onChange, label, disabled }) => (
  <button
    type="button"
    role="switch"
    aria-checked={checked}
    aria-label={label}
    disabled={disabled}
    onClick={() => onChange(!checked)}
    className={`relative w-11 h-6 rounded-full flex-shrink-0 transition-colors disabled:opacity-60 disabled:cursor-not-allowed ${checked ? 'bg-amber-500' : 'bg-slate-600'}`}
  >
    <span className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white transition-transform ${checked ? 'translate-x-5' : ''}`} />
  </button>
);

