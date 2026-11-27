import { useState, useEffect, useCallback, useMemo } from 'react';
import { RefreshCw, AlertCircle, Save, CheckCircle } from 'lucide-react';
import { getTunables, updateTunables, errorMessage, canWrite, ApiError } from './api';
import { card } from './appControlShared';
import TunableField from './TunableField';
import { toDraft, parseDraft, sameValue, formatValue } from './tunablesShared';

const GROUP_ORDER = ['Trial and plans', 'Reminders', 'Unusual spending', 'Family', 'Job times'];

const detailOf = (err) => (err instanceof ApiError && err.detail && typeof err.detail === 'object' && !Array.isArray(err.detail)
  ? err.detail : null);

const Tunables = ({ token, adminRole, ...props }) => {
  const { ConfirmDialog } = props; // the page's in-page confirm dialog (a var, so the lint pattern for components applies)
  const writable = canWrite(adminRole);
  const [settings, setSettings] = useState([]);
  const [version, setVersion] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [drafts, setDrafts] = useState({});        // key -> the form state of a setting the person touched
  const [serverErrors, setServerErrors] = useState({}); // key -> message from a 422
  const [conflict, setConflict] = useState(null);  // { message, reloaded }
  const [saveError, setSaveError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [reloading, setReloading] = useState(false);
  const [showServer, setShowServer] = useState(false); // after a Reload with edits: show the server's values beside them

  const fetchAll = useCallback(async () => {
    try {
      const data = await getTunables(token);
      setSettings(data.settings);
      setVersion(data.version);
      setLoadError(null);
      return null;
    } catch (err) {
      const msg = errorMessage(err, 'Failed to load the settings');
      setLoadError(msg);
      return msg;
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    fetchAll();
  }, [fetchAll]);

  // One entry per setting: what the box holds, what it parses to, whether it is edited or differs from the default.
  const rows = useMemo(() => settings.map((s) => {
    const draft = s.key in drafts ? drafts[s.key] : toDraft(s, s.value);
    const parsed = parseDraft(s, draft);
    const edited = s.key in drafts && (!!parsed.error || !sameValue(parsed.value, s.value));
    const current = parsed.error ? s.value : parsed.value;
    return { s, draft, parsed, edited, changed: !sameValue(current, s.default), current };
  }), [settings, drafts]);

  const edits = rows.filter((r) => r.edited);
  const hasLocalError = edits.some((r) => r.parsed.error);

  const groups = useMemo(() => {
    const names = [...GROUP_ORDER, ...rows.map((r) => r.s.group).filter((g) => !GROUP_ORDER.includes(g))];
    return [...new Set(names)].map((name) => ({ name, items: rows.filter((r) => r.s.group === name) }))
      .filter((g) => g.items.length > 0);
  }, [rows]);

  const setDraft = (key, value) => {
    setDrafts((d) => ({ ...d, [key]: value }));
    setServerErrors((e) => {
      // the cross-field rule ties these two: a message under either one is stale once either is edited
      const gone = key === 'trial_days' || key === 'ends_soon_days' ? ['trial_days', 'ends_soon_days'] : [key];
      if (!gone.some((k) => k in e)) return e;
      return Object.fromEntries(Object.entries(e).filter(([k]) => !gone.includes(k)));
    });
    setSaveError(null);
    setSaved(false);
  };

  const save = async () => {
    setBusy(true);
    setSaveError(null);
    setServerErrors({});
    try {
      const values = Object.fromEntries(edits.map((r) => [r.s.key, r.parsed.value]));
      const data = await updateTunables(token, { values, version });
      setSettings(data.settings);
      setVersion(data.version);
      setDrafts({});
      setConflict(null);
      setShowServer(false);
      setSaved(true);
    } catch (err) {
      const d = detailOf(err);
      if (err instanceof ApiError && err.status === 409) {
        setConflict({ message: d?.message || err.message, reloaded: false });
      } else if (err instanceof ApiError && err.status === 422 && d?.errors) {
        setServerErrors(d.errors);
        setSaveError('Some values were not accepted. Fix them below and save again.');
      } else {
        setSaveError(errorMessage(err, 'Could not save the settings'));
      }
    } finally {
      setConfirming(false);
      setBusy(false);
    }
  };

  // After a conflict: refetch the server's values and version; the edited boxes keep their typing.
  const reload = async () => {
    setReloading(true);
    const failed = await fetchAll();
    setReloading(false);
    if (failed) setSaveError(failed);
    else {
      setSaveError(null);
      setServerErrors({});
      setShowServer(true);
      setConflict((c) => (c ? { ...c, reloaded: true } : c));
    }
  };

  const reloadAll = async () => {
    setLoading(true);
    const failed = await fetchAll();
    if (!failed) setShowServer(true);
  };

  if (loading && settings.length === 0) {
    return <div className="flex items-center justify-center p-20"><RefreshCw size={32} className="animate-spin text-blue-500" /></div>;
  }

  return (
    <div className="animate-slideIn">
      <div className="mb-8 mt-2 md:mt-0 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            Numbers &amp; times
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            Trial length, reminder days, unusual-spending bars and job times{writable ? '' : ' (read-only)'}. Changes apply within a minute.
          </p>
        </div>
        <button onClick={reloadAll} title="Reload" aria-label="Reload"
          className="p-3 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 hover:bg-slate-500/30 flex-shrink-0">
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {loadError && (
        <div className="p-6 bg-red-500/5 border border-red-500/20 rounded-2xl flex flex-col md:flex-row items-start md:items-center gap-4 mb-6">
          <AlertCircle size={22} className="text-red-400 flex-shrink-0" />
          <div className="flex-1 text-sm text-red-300">{loadError}</div>
          <button onClick={reloadAll} className="px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-300 text-sm font-semibold hover:bg-red-500/25 flex items-center gap-2">
            <RefreshCw size={14} /> Retry
          </button>
        </div>
      )}

      {conflict && (
        <div role="alert" className="p-4 bg-amber-500/5 border border-amber-500/30 rounded-2xl flex flex-col md:flex-row items-start md:items-center gap-3 mb-6">
          <AlertCircle size={20} className="text-amber-400 flex-shrink-0" />
          <div className="flex-1 min-w-0 text-sm text-amber-200">
            {conflict.reloaded
              ? 'Reloaded. Your edits are kept; the server\'s values are shown beside them. Check them and save again.'
              : conflict.message}
          </div>
          {!conflict.reloaded && (
            <button type="button" onClick={reload} disabled={reloading}
              className="px-4 py-2 bg-amber-500/15 border border-amber-500/30 rounded-lg text-amber-200 text-sm font-semibold hover:bg-amber-500/25 flex items-center gap-2 disabled:opacity-40">
              <RefreshCw size={14} className={reloading ? 'animate-spin' : ''} /> Reload
            </button>
          )}
        </div>
      )}

      {groups.map((g) => (
        <div key={g.name} className="mb-8">
          <h2 className="text-base font-bold text-slate-200 mb-3">{g.name}</h2>
          <div className={`${card} overflow-hidden`}>
            {g.items.map((r) => (
              <TunableField key={r.s.key} setting={r.s} draft={r.draft} disabled={!writable || busy}
                onChange={(v) => setDraft(r.s.key, v)}
                error={(r.s.key in drafts && r.parsed.error) || serverErrors[r.s.key] || null}
                serverNow={showServer && r.edited ? formatValue(r.s, r.s.value) : null}
                changed={r.changed} canReset={writable && r.changed}
                onUseDefault={() => setDraft(r.s.key, toDraft(r.s, r.s.default))} />
            ))}
          </div>
        </div>
      ))}

      {writable && settings.length > 0 && (
        <div className="mb-8 flex flex-wrap items-center gap-3">
          <button type="button" onClick={() => setConfirming(true)} disabled={busy || edits.length === 0 || hasLocalError}
            className="px-5 py-2.5 bg-blue-500 hover:bg-blue-600 rounded-xl text-white text-sm font-semibold flex items-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed">
            {busy ? <RefreshCw size={15} className="animate-spin" /> : <Save size={15} />}
            Save
          </button>
          {edits.length > 0 && !busy && <span className="text-sm text-slate-400">{edits.length} unsaved {edits.length === 1 ? 'change' : 'changes'}</span>}
          {saved && edits.length === 0 && (
            <span className="text-sm text-emerald-300 flex items-center gap-1.5"><CheckCircle size={15} /> Saved</span>
          )}
          {saveError && (
            <span role="alert" className="text-sm text-red-300 flex items-center gap-1.5 min-w-0">
              <AlertCircle size={15} className="flex-shrink-0" /> <span className="break-words">{saveError}</span>
            </span>
          )}
        </div>
      )}

      {confirming && (
        <ConfirmDialog
          title="Save these changes?"
          confirmLabel="Save"
          tone="warning"
          busy={busy}
          onCancel={() => setConfirming(false)}
          onConfirm={save}
          message={(
            <ul className="space-y-1.5">
              {edits.map((r) => (
                <li key={r.s.key} className="break-words">
                  <span className="font-semibold text-slate-100">{r.s.label}:</span>{' '}
                  {formatValue(r.s, r.s.value)} <span className="text-slate-500">&rarr;</span> {formatValue(r.s, r.parsed.value)}
                </li>
              ))}
            </ul>
          )}
        />
      )}
    </div>
  );
};

export default Tunables;
