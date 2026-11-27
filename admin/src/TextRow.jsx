import { useState } from 'react';
import { RefreshCw, Save, RotateCcw, AlertCircle, AlertTriangle } from 'lucide-react';
import { apiRequest, errorMessage, ApiError } from './api';
import { field } from './appControlShared';
import { Counter } from './AppControlParts';

export const MAX_TEXT = 1000;
const LANGS = [
  { id: 'en', label: 'English' },
  { id: 'my', label: 'Myanmar' },
];

const detailMessage = (err) => {
  if (err instanceof ApiError && err.detail && typeof err.detail === 'object' && !Array.isArray(err.detail)) {
    return err.detail.message || err.message;
  }
  return errorMessage(err, 'Request failed');
};
const isConflict = (err) => err instanceof ApiError && err.status === 409;

/** One language of one text: the editor, its default, and Save / Reset. */
const LangEditor = ({ textKey, lang, label, def, override, writable, token, onChanged, onReload, ...props }) => {
  const { ConfirmDialog } = props; // the page's in-page confirm dialog
  const current = override ? override.text : def;
  const [value, setValue] = useState(current);
  const [base, setBase] = useState(current); // what the box held when it was last in step with the server
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);   // { message, conflict }
  const [confirming, setConfirming] = useState(false);
  const [reloading, setReloading] = useState(false);
  const [reloaded, setReloaded] = useState(false); // after a conflict the page refetched: show the server's text next to the draft

  // The server's text changed under us (saved here, reset, or reloaded): follow it unless the person is typing.
  if (current !== base) {
    setBase(current);
    if (value === base) setValue(current);
  }

  const dirty = value !== current;
  const tooLong = value.length > MAX_TEXT;
  const path = `/api/admin/texts/${encodeURIComponent(textKey)}/${lang}`;

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      const res = await apiRequest(path, {
        token, method: 'PUT', body: { text: value, version: override ? override.version : null },
      });
      // The server trims, and answers null when the text equals the default (no override is kept).
      setValue(res ? res.text : def);
      setReloaded(false);
      onChanged(lang, res);
    } catch (err) {
      setError({ message: detailMessage(err), conflict: isConflict(err) });
    } finally {
      setBusy(false);
    }
  };

  const reset = async () => {
    setBusy(true);
    setError(null);
    try {
      await apiRequest(path, { token, method: 'DELETE', params: { version: override.version } });
      setConfirming(false);
      setValue(def);
      setReloaded(false);
      onChanged(lang, null);
    } catch (err) {
      setConfirming(false);
      setError({ message: detailMessage(err), conflict: isConflict(err) });
    } finally {
      setBusy(false);
    }
  };

  // Refetch after a conflict. The draft stays; the server's current text is shown beside it so the redo is deliberate.
  const reloadText = async () => {
    setReloading(true);
    const failed = await onReload();
    setReloading(false);
    if (failed) {
      setError({ message: failed, conflict: true });
    } else {
      setError(null);
      setReloaded(true);
    }
  };

  const id = `text-${textKey}-${lang}`;
  return (
    <div className="min-w-0">
      <div className="flex items-center gap-2 mb-1.5">
        <label htmlFor={id} className="text-xs font-semibold text-slate-400">{label}</label>
        {override && <span className="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded bg-blue-500/15 text-blue-300">Changed</span>}
      </div>
      <textarea id={id} lang={lang} rows={3} value={value} readOnly={!writable || busy}
        onChange={(e) => setValue(e.target.value)} className={`${field} resize-y`} />
      <Counter value={value} max={MAX_TEXT} />

      {override && (
        <div className="mt-2 text-xs text-slate-500">
          <span className="font-semibold text-slate-400">Default: </span>
          <span lang={lang} className="whitespace-pre-wrap break-words">{def}</span>
        </div>
      )}
      {override?.invalid && (
        <div role="alert" className="mt-2 flex items-start gap-1.5 text-xs text-amber-300">
          <AlertTriangle size={14} className="flex-shrink-0 mt-px" />
          <span className="min-w-0 break-words">
            Your edit no longer fits this text ({override.invalid}); the default is used. Fix it and save, or reset.
          </span>
        </div>
      )}
      {reloaded && dirty && (
        <div className="mt-2 p-2.5 bg-amber-500/5 border border-amber-500/20 rounded-lg text-xs text-amber-200">
          <div className="font-semibold mb-1">Someone else changed this. The text on the server now (your typing is kept above):</div>
          <div lang={lang} className="whitespace-pre-wrap break-words text-slate-300">{current}</div>
        </div>
      )}
      {override?.default_changed && !override.invalid && (
        <div className="mt-2 flex items-start gap-1.5 text-xs text-amber-300">
          <AlertTriangle size={14} className="flex-shrink-0 mt-px" />
          <span>Default changed since your edit. Check that your text still fits.</span>
        </div>
      )}

      {error && (
        <div role="alert" className="mt-2 p-2.5 bg-red-500/5 border border-red-500/20 rounded-lg text-xs text-red-300">
          <div className="flex items-start gap-1.5 min-w-0">
            <AlertCircle size={14} className="flex-shrink-0 mt-px" />
            <span className="min-w-0 break-words">{error.message}</span>
          </div>
          {error.conflict && (
            <button type="button" onClick={reloadText} disabled={reloading}
              className="mt-2 px-3 py-1 bg-red-500/15 border border-red-500/30 rounded-lg text-red-200 font-semibold hover:bg-red-500/25 disabled:opacity-40">
              {reloading ? 'Reloading...' : 'Reload this text'}
            </button>
          )}
        </div>
      )}

      {writable && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <button type="button" onClick={save} disabled={busy || !dirty || tooLong}
            className="px-4 py-2 bg-blue-500 hover:bg-blue-600 rounded-xl text-white text-xs font-semibold flex items-center gap-1.5 disabled:opacity-40 disabled:cursor-not-allowed">
            {busy ? <RefreshCw size={13} className="animate-spin" /> : <Save size={13} />}
            Save
          </button>
          {override && (
            <button type="button" onClick={() => setConfirming(true)} disabled={busy}
              className="px-4 py-2 bg-slate-500/20 border border-slate-500/30 hover:bg-slate-500/30 rounded-xl text-slate-300 text-xs font-semibold flex items-center gap-1.5 disabled:opacity-40">
              <RotateCcw size={13} /> Reset
            </button>
          )}
          {dirty && !busy && <span className="text-xs text-slate-400">Unsaved</span>}
        </div>
      )}

      {confirming && (
        <ConfirmDialog
          title="Reset to the default?"
          confirmLabel="Reset"
          busy={busy}
          onCancel={() => setConfirming(false)}
          onConfirm={reset}
          message={`Your ${label} text for ${textKey} is removed and the built-in default is used again.`}
        />
      )}
    </div>
  );
};

const TextRow = ({ item, writable, token, ConfirmDialog, onChanged, onReload }) => (
  <div className="p-4 border-b border-white/5 last:border-b-0">
    <div className="mb-3 min-w-0">
      <div className="text-sm font-bold text-slate-100 break-all">{item.key}</div>
      <div className="text-xs text-slate-500">
        {item.area} · {item.placeholders.length
          ? `Must keep: ${item.placeholders.map((p) => `{${p}}`).join(', ')}`
          : 'No placeholders'}
      </div>
    </div>
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      {LANGS.map((l) => (
        <LangEditor key={l.id} textKey={item.key} lang={l.id} label={l.label}
          def={item.default[l.id] ?? ''} override={item.override?.[l.id] ?? null}
          writable={writable} token={token} ConfirmDialog={ConfirmDialog}
          onChanged={(lang, ov) => onChanged(item.key, lang, ov)}
          onReload={() => onReload()} />
      ))}
    </div>
  </div>
);

export default TextRow;
