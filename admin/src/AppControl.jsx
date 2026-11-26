import { useState, useEffect, useCallback, useMemo } from 'react';
import { RefreshCw, AlertCircle, AlertTriangle, Save, ToggleLeft, Wrench } from 'lucide-react';
import { apiRequest, errorMessage, canWrite } from './api';
import Announcements from './Announcements';
import {
  MAX_MESSAGE, card, field, isoToLocalInput, localInputToIso, errorLines,
} from './appControlShared';
import { ErrorBox, NoticeBox, Counter, Toggle } from './AppControlParts';

const MAX_TESTERS = 50;
const STANDARD_MAINTENANCE = 'Toe Pwar is under maintenance. Please try again soon.';

// The sections of switches, in the order they appear.
const GROUPS = [
  { title: 'Ko Toe Pwar features', hint: 'AI features. Pausing one refuses new requests; saved reports, chat history and stored translations stay readable.', keys: ['chat', 'voice', 'receipts', 'budget_ideas', 'reports', 'custom_reports', 'translation'] },
  { title: 'Accounts', hint: 'Who can join.', keys: ['signups', 'free_trial'] },
  { title: 'Family', hint: 'Family books.', keys: ['family_new'] },
];

// ─── Draft <-> document ───────────────────────────────────────────────────────
const toDraft = (doc, keys) => ({
  switches: Object.fromEntries(keys.map((k) => {
    const s = doc.switches?.[k] ?? {};
    return [k, { paused: !!s.paused, en: s.message_en ?? '', my: s.message_my ?? '' }];
  })),
  maintenance: {
    on: !!doc.maintenance?.on,
    en: doc.maintenance?.message_en ?? '',
    my: doc.maintenance?.message_my ?? '',
    backBy: isoToLocalInput(doc.maintenance?.back_by),
    testers: (doc.maintenance?.testers ?? []).join('\n'),
  },
});

const parseTesters = (text) => text.split('\n').map((t) => t.trim()).filter(Boolean);

const toBody = (draft) => ({
  switches: Object.fromEntries(Object.entries(draft.switches).map(([k, s]) => [k, {
    paused: s.paused, message_en: s.en.trim(), message_my: s.my.trim(),
  }])),
  maintenance: {
    on: draft.maintenance.on,
    message_en: draft.maintenance.en.trim(),
    message_my: draft.maintenance.my.trim(),
    back_by: localInputToIso(draft.maintenance.backBy),
    testers: parseTesters(draft.maintenance.testers),
  },
});

const MessageFields = ({ idPrefix, en, my, onEn, onMy }) => (
  <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
    <div className="min-w-0">
      <label htmlFor={`${idPrefix}-en`} className="block text-xs font-semibold text-slate-400 mb-1.5">English message (optional)</label>
      <textarea id={`${idPrefix}-en`} lang="en" rows={2} value={en} onChange={(e) => onEn(e.target.value)} className={`${field} resize-y`} />
      <Counter value={en} max={MAX_MESSAGE} />
    </div>
    <div className="min-w-0">
      <label htmlFor={`${idPrefix}-my`} className="block text-xs font-semibold text-slate-400 mb-1.5">Myanmar message (optional)</label>
      <textarea id={`${idPrefix}-my`} lang="my" rows={2} value={my} onChange={(e) => onMy(e.target.value)} className={`${field} resize-y`} />
      <Counter value={my} max={MAX_MESSAGE} />
    </div>
  </div>
);

const Preview = ({ text }) => (
  <p className="mt-3 text-xs text-slate-400">
    <span className="font-semibold text-slate-300">Users see: </span>{text}
  </p>
);

const SwitchRow = ({ name, id, value, onChange }) => {
  const standard = `Paused for now: ${name}. Please try again later.`;
  return (
    <div className="p-4 border-b border-white/5 last:border-b-0">
      <div className="flex items-center justify-between gap-4 mb-3">
        <div className="min-w-0">
          <div className="text-sm font-bold text-slate-100">{name}</div>
          <div className="text-xs text-slate-500 break-all">{id}</div>
        </div>
        <div className="flex items-center gap-3 flex-shrink-0">
          <span className={`text-xs font-semibold ${value.paused ? 'text-amber-300' : 'text-slate-500'}`}>{value.paused ? 'Paused' : 'Running'}</span>
          <Toggle checked={value.paused} label={`Pause ${name}`} onChange={(paused) => onChange({ ...value, paused })} />
        </div>
      </div>
      <MessageFields idPrefix={`switch-${id}`} en={value.en} my={value.my}
        onEn={(en) => onChange({ ...value, en })} onMy={(my) => onChange({ ...value, my })} />
      <Preview text={value.en.trim() || standard} />
    </div>
  );
};

/** Problems the form can see before asking the server (the server's 422 stays the source of truth). */
const findProblems = (draft, nameOf) => {
  const out = [];
  for (const [k, s] of Object.entries(draft.switches)) {
    if (s.en.length > MAX_MESSAGE || s.my.length > MAX_MESSAGE) out.push(`${nameOf(k)}: messages can be at most ${MAX_MESSAGE} characters`);
  }
  const m = draft.maintenance;
  if (m.en.length > MAX_MESSAGE || m.my.length > MAX_MESSAGE) out.push(`Maintenance: messages can be at most ${MAX_MESSAGE} characters`);
  const testers = parseTesters(m.testers);
  if (testers.length > MAX_TESTERS) out.push(`Maintenance: at most ${MAX_TESTERS} testers`);
  const bad = testers.find((t) => !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(t));
  if (bad) out.push(`Maintenance: "${bad}" is not a valid email address`);
  if (m.backBy && !localInputToIso(m.backBy)) out.push('Maintenance: the "back by" time is not valid');
  return out;
};

// ─── Page ─────────────────────────────────────────────────────────────────────
const AppControl = ({ token, adminRole, ...props }) => {
  const { ConfirmDialog } = props; // the page's in-page confirm dialog
  const writable = canWrite(adminRole);
  const [saved, setSaved] = useState(null);       // the document from the server
  const [switches, setSwitches] = useState([]);   // [{key, name_en}]
  const [draft, setDraft] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);   // { errors, notice }
  const [confirming, setConfirming] = useState(false);

  const keys = useMemo(() => switches.map((s) => s.key), [switches]);
  const nameOf = useCallback((k) => switches.find((s) => s.key === k)?.name_en ?? k, [switches]);

  const fetchSettings = useCallback(async () => {
    try {
      const data = await apiRequest('/api/admin/app-control', { token });
      setSwitches(data.switches);
      setSaved(data.settings);
      setDraft(toDraft(data.settings, data.switches.map((s) => s.key)));
      setLoadError(null);
    } catch (err) {
      setLoadError(errorMessage(err, 'Failed to load App control'));
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    fetchSettings();
  }, [fetchSettings]);

  const reload = () => {
    setLoading(true);
    setMessage(null);
    fetchSettings();
  };

  const problems = useMemo(() => (draft ? findProblems(draft, nameOf) : []), [draft, nameOf]);
  const dirty = useMemo(
    () => !!(saved && draft) && JSON.stringify(draft) !== JSON.stringify(toDraft(saved, keys)),
    [saved, draft, keys],
  );

  const setSwitch = (key, value) => setDraft((d) => ({ ...d, switches: { ...d.switches, [key]: value } }));
  const setMaintenance = (patch) => setDraft((d) => ({ ...d, maintenance: { ...d.maintenance, ...patch } }));

  const doSave = async () => {
    setConfirming(false);
    setBusy(true);
    setMessage(null);
    try {
      const res = await apiRequest('/api/admin/app-control', { token, method: 'PUT', body: toBody(draft) });
      setSaved(res);
      setDraft(toDraft(res, keys));
      setMessage({ notice: 'Saved. The app picks up the change within about a minute.' });
    } catch (err) {
      setMessage({ errors: errorLines(err) });
    } finally {
      setBusy(false);
    }
  };

  // Maintenance turning on, or sign-ups getting paused, is the kind of change that locks people out: ask first.
  const needsConfirm = !!(saved && draft) && (
    (draft.maintenance.on && !saved.maintenance?.on)
    || (draft.switches.signups?.paused && !saved.switches?.signups?.paused)
  );
  const handleSave = () => (needsConfirm ? setConfirming(true) : doSave());

  if (loading && !draft) {
    return <div className="flex items-center justify-center p-20"><RefreshCw size={32} className="animate-spin text-blue-500" /></div>;
  }

  const testers = draft ? parseTesters(draft.maintenance.testers) : [];
  const turningMaintenanceOn = !!draft && draft.maintenance.on && !saved?.maintenance?.on;
  const pausingSignups = !!draft && draft.switches.signups?.paused && !saved?.switches?.signups?.paused;
  const testerText = testers.length ? `Only these testers can still get in: ${testers.join(', ')}.` : 'Nobody is listed as a tester, so nobody can get in.';

  return (
    <div className="animate-slideIn">
      <div className="mb-8 mt-2 md:mt-0 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            App control
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            Pause features, put the app into maintenance, and show announcements{writable ? '' : ' (read-only)'}
          </p>
        </div>
        <button onClick={reload} title="Reload" aria-label="Reload"
          className="p-3 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 hover:bg-slate-500/30 flex-shrink-0">
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {loadError && (
        <div className="p-6 bg-red-500/5 border border-red-500/20 rounded-2xl flex flex-col md:flex-row items-start md:items-center gap-4 mb-6">
          <AlertCircle size={22} className="text-red-400 flex-shrink-0" />
          <div className="flex-1 text-sm text-red-300">{loadError}</div>
          <button onClick={reload} className="px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-300 text-sm font-semibold hover:bg-red-500/25 flex items-center gap-2">
            <RefreshCw size={14} /> Retry
          </button>
        </div>
      )}

      {draft && (
        <>
          <fieldset disabled={!writable || busy} className="border-0 p-0 m-0 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <Wrench size={20} className="text-amber-400" />
              <h2 className="text-xl font-bold text-slate-100">Maintenance</h2>
            </div>
            <p className="text-slate-400 text-sm mb-4">
              While on, everyone is told the app is under maintenance, except the testers listed here. This panel keeps working.
            </p>
            <div className={`${card} p-5 mb-8`}>
              <div className="flex items-center justify-between gap-4 mb-4">
                <div className="text-sm font-bold text-slate-100">Maintenance mode</div>
                <div className="flex items-center gap-3">
                  <span className={`text-xs font-semibold ${draft.maintenance.on ? 'text-amber-300' : 'text-slate-500'}`}>{draft.maintenance.on ? 'On' : 'Off'}</span>
                  <Toggle checked={draft.maintenance.on} label="Maintenance mode" onChange={(on) => setMaintenance({ on })} />
                </div>
              </div>
              <MessageFields idPrefix="maintenance" en={draft.maintenance.en} my={draft.maintenance.my}
                onEn={(en) => setMaintenance({ en })} onMy={(my) => setMaintenance({ my })} />
              <Preview text={draft.maintenance.en.trim() || STANDARD_MAINTENANCE} />
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-5">
                <div className="min-w-0">
                  <label htmlFor="maintenance-back-by" className="block text-xs font-semibold text-slate-400 mb-1.5">Back by (optional, your local time)</label>
                  <input id="maintenance-back-by" type="datetime-local" value={draft.maintenance.backBy}
                    onChange={(e) => setMaintenance({ backBy: e.target.value })} className={field} />
                </div>
                <div className="min-w-0">
                  <label htmlFor="maintenance-testers" className="block text-xs font-semibold text-slate-400 mb-1.5">Testers who can still get in (one email per line)</label>
                  <textarea id="maintenance-testers" rows={3} value={draft.maintenance.testers}
                    placeholder="you@example.com" onChange={(e) => setMaintenance({ testers: e.target.value })} className={`${field} resize-y`} />
                  <div className={`text-xs mt-1 ${testers.length > MAX_TESTERS ? 'text-red-300' : 'text-slate-500'}`}>{testers.length}/{MAX_TESTERS} testers</div>
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2 mb-1">
              <ToggleLeft size={20} className="text-blue-400" />
              <h2 className="text-xl font-bold text-slate-100">Features</h2>
            </div>
            <p className="text-slate-400 text-sm mb-4">
              Each switch pauses one thing for everyone. Leave a message empty to show the standard sentence.
            </p>
            {GROUPS.map((group) => (
              <div key={group.title} className="mb-8">
                <h3 className="text-base font-bold text-slate-200 mb-1">{group.title}</h3>
                <p className="text-slate-500 text-xs mb-3">{group.hint}</p>
                <div className={`${card} overflow-hidden`}>
                  {group.keys.filter((k) => draft.switches[k]).map((k) => (
                    <SwitchRow key={k} id={k} name={nameOf(k)} value={draft.switches[k]} onChange={(v) => setSwitch(k, v)} />
                  ))}
                </div>
              </div>
            ))}
          </fieldset>

          {writable && (
            <div className="space-y-3 mb-8">
              {problems.length > 0 && (
                <div className="p-3 bg-amber-500/10 border border-amber-500/20 rounded-xl text-xs text-amber-200 space-y-1">
                  {problems.map((p, i) => (
                    <div key={i} className="flex items-start gap-1.5 min-w-0">
                      <AlertTriangle size={14} className="flex-shrink-0 mt-px" />
                      <span className="min-w-0 break-words">{p}</span>
                    </div>
                  ))}
                </div>
              )}
              <div className="flex flex-wrap items-center gap-3">
                <button onClick={handleSave} disabled={busy || !dirty || problems.length > 0}
                  className="px-5 py-2.5 bg-blue-500 hover:bg-blue-600 rounded-xl text-white text-sm font-semibold flex items-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed">
                  {busy ? <RefreshCw size={15} className="animate-spin" /> : <Save size={15} />}
                  Save
                </button>
                {dirty && !busy && <span className="text-xs text-slate-400">Unsaved changes</span>}
              </div>
            </div>
          )}

          <ErrorBox lines={message?.errors} />
          <NoticeBox text={message?.notice} />

          <Announcements token={token} writable={writable} ConfirmDialog={ConfirmDialog} />
        </>
      )}

      {confirming && (
        <ConfirmDialog
          title={turningMaintenanceOn ? 'Turn maintenance on?' : 'Pause sign-ups?'}
          tone="warning"
          confirmLabel="Save"
          busy={busy}
          onCancel={() => setConfirming(false)}
          onConfirm={doSave}
          message={(
            <div className="space-y-2">
              {turningMaintenanceOn && <p>Everyone except the testers will see the maintenance message and be locked out of the app. {testerText}</p>}
              {pausingSignups && <p>New people will not be able to sign up until you resume sign-ups.</p>}
            </div>
          )}
        />
      )}
    </div>
  );
};

export default AppControl;
