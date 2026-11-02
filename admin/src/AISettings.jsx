import { useState, useEffect, useCallback } from 'react';
import {
  Bot, RefreshCw, AlertCircle, CheckCircle, AlertTriangle, ArrowUp, ArrowDown, Plus, X, Play, Save, RotateCcw,
} from 'lucide-react';
import {
  errorMessage, formatErrorDetail, canWrite, ApiError,
  getAISettings, updateAISetting, resetAISetting, getAIStatus, testAIProvider,
} from './api';

const STATUS_REFRESH_MS = 30000;
const OTHER = '__other__';

const PROVIDER_LABELS = { openai: 'OpenAI', gemini: 'Gemini', claude: 'Claude' };
const SOURCE_LABELS = { panel: 'Admin panel', server: 'Server setting', default: 'Built-in' };
const SOURCE_CLASSES = {
  panel: 'bg-blue-500/15 border-blue-500/30 text-blue-300',
  server: 'bg-violet-500/15 border-violet-500/30 text-violet-300',
  default: 'bg-slate-500/15 border-slate-400/20 text-slate-300',
};

const providerLabel = (p) => PROVIDER_LABELS[p] ?? String(p);
const targetText = (t) => `${providerLabel(t.provider)} ${t.model}`;
const fmtTime = (iso) => new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
const fmtDateTime = (iso) => new Date(iso).toLocaleString();

const card = 'bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5';
const field = 'w-full min-w-0 px-3 py-2.5 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 disabled:opacity-60 disabled:cursor-not-allowed';
const iconBtn = 'p-2 rounded-lg bg-slate-500/15 border border-slate-400/20 text-slate-300 hover:bg-slate-500/25 disabled:opacity-30 disabled:cursor-not-allowed';

// ─── Draft helpers ────────────────────────────────────────────────────────────
const toDraftTarget = (t, knownModels) => ({
  provider: t.provider,
  model: t.model,
  other: !(knownModels[t.provider] ?? []).includes(t.model),
});

const toDraft = (row, knownModels) => {
  const eff = row.effective;
  return {
    main: toDraftTarget(eff.main, knownModels),
    mode: eff.backups == null ? 'default' : eff.backups.length === 0 ? 'none' : 'custom',
    backups: (eff.backups ?? []).map((b) => toDraftTarget(b, knownModels)),
  };
};

/** The model to pick when the provider of a target changes: the first one the feature offers for it. */
const suggestModel = (provider, knownModels) => (knownModels[provider] ?? [])[0] ?? '';

const toBody = (draft) => ({
  main: { provider: draft.main.provider, model: draft.main.model.trim() },
  backups: draft.mode === 'default' ? null
    : draft.mode === 'none' ? []
      : draft.backups.map((b) => ({ provider: b.provider, model: b.model.trim() })),
});

const dupKey = (t) => `${t.provider}:${t.model.trim()}`;

/** First provider:model pair that is already listed twice (main + custom backups), or null. */
const findDuplicate = (draft) => {
  const list = draft.mode === 'custom' ? [draft.main, ...draft.backups] : [draft.main];
  const seen = new Set();
  for (const t of list) {
    const k = dupKey(t);
    if (t.model.trim() && seen.has(k)) return k;
    seen.add(k);
  }
  return null;
};

/** 422 detail: a list of strings (semantic checks) or of pydantic error dicts. One readable line each. */
const errorLines = (err) => {
  if (err instanceof ApiError && err.status === 422) {
    const d = err.detail;
    if (Array.isArray(d)) {
      const lines = d.map((x) => formatErrorDetail([x], '')).filter(Boolean);
      if (lines.length) return lines;
    }
    return [formatErrorDetail(d, err.message)];
  }
  return [errorMessage(err, 'Request failed')];
};

// ─── Status cards ─────────────────────────────────────────────────────────────
const StateChip = ({ p }) => {
  const base = 'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-semibold';
  switch (p.state) {
    case 'working':
      return <span className={`${base} bg-emerald-500/15 border-emerald-500/30 text-emerald-300`}>working</span>;
    case 'failing':
      return <span className={`${base} bg-red-500/15 border-red-500/30 text-red-300`}>failing</span>;
    case 'cooling':
      return (
        <span className={`${base} bg-amber-500/15 border-amber-500/30 text-amber-300`}>
          cooling{p.cooling_until ? ` until ${fmtTime(p.cooling_until)}` : ''}
        </span>
      );
    default:
      return <span className={`${base} bg-slate-500/15 border-slate-400/20 text-slate-300`}>unused</span>;
  }
};

const StatusCard = ({ provider, status, writable, testing, testResult, onTest }) => {
  const label = providerLabel(provider.id);
  const configured = provider.configured;
  return (
    <div className={`${card} p-5 min-w-0`}>
      <div className="flex flex-wrap items-center justify-between gap-2 mb-4">
        <h3 className="text-lg font-bold text-slate-100">{label}</h3>
        <span className={`px-2.5 py-1 rounded-full border text-xs font-semibold ${configured
          ? 'bg-emerald-500/10 border-emerald-500/25 text-emerald-300'
          : 'bg-red-500/10 border-red-500/25 text-red-300'}`}>
          {configured ? 'Configured' : 'Not configured'}
        </span>
      </div>

      {status ? (
        <div className="space-y-3 text-sm">
          <div className="flex items-center justify-between gap-3">
            <span className="text-slate-400">State</span>
            <StateChip p={status} />
          </div>
          <div className="flex items-center justify-between gap-3">
            <span className="text-slate-400">Last success</span>
            <span className="text-slate-200 text-right">{status.last_success_at ? fmtDateTime(status.last_success_at) : 'never'}</span>
          </div>
          <div className="flex items-center justify-between gap-3">
            <span className="text-slate-400">Backup answers (24 h)</span>
            <span className="text-slate-200 font-semibold">{status.backup_answers_24h ?? 0}</span>
          </div>
          {status.cooling_models?.length > 0 && (
            <div>
              <div className="text-slate-400 mb-1">Cooling models</div>
              <ul className="space-y-1">
                {status.cooling_models.map((m) => (
                  <li key={m.model} className="text-xs text-amber-200 bg-amber-500/10 border border-amber-500/20 rounded-lg px-2.5 py-1.5 break-all">
                    {m.model} until {fmtTime(m.until)}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {status.last_error && (
            <div>
              <div className="text-slate-400 mb-1">
                Last error{status.last_error_at ? <span className="text-slate-500"> · {fmtDateTime(status.last_error_at)}</span> : null}
              </div>
              <div className="text-xs text-red-300 bg-red-500/5 border border-red-500/20 rounded-lg px-2.5 py-2 break-words">{status.last_error}</div>
            </div>
          )}
        </div>
      ) : (
        <div className="text-sm text-slate-500">No status yet</div>
      )}

      {writable && (
        <div className="mt-4 pt-4 border-t border-white/5">
          <button
            onClick={() => onTest(provider.id)}
            disabled={!configured || testing}
            title={configured ? undefined : 'No API key configured on the server'}
            className="w-full px-4 py-2.5 bg-blue-500/15 border border-blue-500/30 rounded-xl text-blue-300 text-sm font-semibold flex items-center justify-center gap-2 hover:bg-blue-500/25 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {testing ? <RefreshCw size={15} className="animate-spin" /> : <Play size={15} />}
            Test
          </button>
          <p className="text-xs text-slate-500 mt-2">sends one tiny request (costs a fraction of a cent)</p>
          {testResult && (
            <div className={`mt-2 text-xs rounded-lg px-2.5 py-2 break-words border ${testResult.ok
              ? 'text-emerald-300 bg-emerald-500/10 border-emerald-500/20'
              : 'text-red-300 bg-red-500/5 border-red-500/20'}`}>
              {testResult.ok ? 'Test succeeded.' : `Test failed: ${testResult.error}`}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

// ─── Feature rows ─────────────────────────────────────────────────────────────
// `knownModels` is the feature's own list ({provider: [models]}), so each picker offers only models that feature can use.
const TargetEditor = ({ target, onChange, allowed, knownModels, configured, label }) => {
  const models = knownModels[target.provider] ?? [];
  const onProvider = (provider) => {
    const model = suggestModel(provider, knownModels);
    onChange({ provider, model, other: false });
  };
  const onModelSelect = (value) => {
    if (value === OTHER) onChange({ ...target, other: true });
    else onChange({ ...target, model: value, other: false });
  };
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 min-w-0">
      <select
        aria-label={`${label.text} provider`}
        value={target.provider}
        onChange={(e) => onProvider(e.target.value)}
        className={`${field} self-start`}
      >
        {allowed.map((p) => (
          <option key={p} value={p}>{providerLabel(p)}{configured[p] === false ? ' (no API key)' : ''}</option>
        ))}
      </select>
      <div className="min-w-0 space-y-2">
        <select
          aria-label={`${label.text} model`}
          value={target.other ? OTHER : target.model}
          onChange={(e) => onModelSelect(e.target.value)}
          className={field}
        >
          {models.map((m) => <option key={m} value={m}>{m}</option>)}
          <option value={OTHER}>Other…</option>
        </select>
        {target.other && (
          <input
            type="text"
            aria-label={`${label.text} model name`}
            value={target.model}
            maxLength={100}
            placeholder="model name"
            onChange={(e) => onChange({ ...target, model: e.target.value })}
            className={field}
          />
        )}
      </div>
    </div>
  );
};

const FeatureCard = ({ row, providers, knownModels, writable, busy, message, onSave, onReset }) => {
  const [draft, setDraft] = useState(() => toDraft(row, knownModels));
  const allowed = row.allowed;
  const configured = Object.fromEntries(providers.map((p) => [p.id, p.configured]));
  const fieldsetDisabled = !writable || busy;

  const setMain = (main) => setDraft((d) => ({ ...d, main }));
  // Choosing "Custom" starts from the default backups, so the admin edits a list instead of building one.
  const setMode = (mode) => setDraft((d) => {
    if (mode === 'custom' && d.mode !== 'custom' && d.backups.length === 0) {
      const start = row.default_chain
        .filter((t) => allowed.includes(t.provider))
        .map((t) => toDraftTarget(t, knownModels));
      return { ...d, mode, backups: start };
    }
    return { ...d, mode };
  });
  const setBackup = (i, t) => setDraft((d) => ({ ...d, backups: d.backups.map((b, j) => (j === i ? t : b)) }));
  const removeBackup = (i) => setDraft((d) => ({ ...d, backups: d.backups.filter((_, j) => j !== i) }));
  const moveBackup = (i, delta) => setDraft((d) => {
    const j = i + delta;
    if (j < 0 || j >= d.backups.length) return d;
    const next = [...d.backups];
    [next[i], next[j]] = [next[j], next[i]];
    return { ...d, backups: next };
  });

  // Add a backup that is not already listed (the server's 422 stays the source of truth).
  const addBackup = () => setDraft((d) => {
    const used = [d.main, ...d.backups];
    const taken = new Set(used.map(dupKey));
    const usedProviders = new Set(used.map((t) => t.provider));
    // Prefer a provider that is not in the list yet, then any free pair.
    for (const onlyNew of [true, false]) {
      for (const p of allowed) {
        if (onlyNew && usedProviders.has(p)) continue;
        const models = knownModels[p] ?? [];
        for (const m of models) {
          if (!taken.has(`${p}:${m}`)) {
            return { ...d, backups: [...d.backups, { provider: p, model: m, other: false }] };
          }
        }
      }
    }
    return d;
  });

  const duplicate = findDuplicate(draft);
  const mainModelMissing = !draft.main.model.trim();
  const backupModelMissing = draft.mode === 'custom' && draft.backups.some((b) => !b.model.trim());
  const canSave = !duplicate && !mainModelMissing && !backupModelMissing;

  const eff = row.effective;
  const sourceKey = SOURCE_LABELS[eff.source] ? eff.source : 'default';
  const defaultText = row.default_chain.length
    ? row.default_chain.map(targetText).join(' → ')
    : 'no other configured provider';
  const mainChanged = draft.main.provider !== eff.main.provider;

  const modeOptions = [
    { id: 'default', label: `Default (${defaultText})` },
    { id: 'none', label: 'No backups' },
    { id: 'custom', label: 'Custom' },
  ];

  return (
    <div className={`${card} p-5 min-w-0`}>
      <div className="flex flex-wrap items-center justify-between gap-2 mb-4">
        <div className="min-w-0">
          <h3 className="text-base font-bold text-slate-100">{row.label}</h3>
          <div className="text-xs text-slate-500 break-all">{row.key}</div>
        </div>
        <span
          className={`px-2.5 py-1 rounded-full border text-xs font-semibold ${SOURCE_CLASSES[sourceKey]}`}
          title="Where the setting in force comes from"
        >
          {SOURCE_LABELS[sourceKey]}
        </span>
      </div>

      <fieldset disabled={fieldsetDisabled} className="min-w-0 space-y-4 border-0 p-0 m-0">
        <div>
          <div className="text-xs font-semibold text-slate-400 uppercase mb-2">Main</div>
          <TargetEditor
            target={draft.main}
            onChange={setMain}
            allowed={allowed}
            knownModels={knownModels}
            configured={configured}
            label={{ text: `${row.label} main` }}
          />
        </div>

        <div>
          <div className="text-xs font-semibold text-slate-400 uppercase mb-2">Backups</div>
          <select
            aria-label={`${row.label} backups`}
            value={draft.mode}
            onChange={(e) => setMode(e.target.value)}
            className={field}
          >
            {modeOptions.map((o) => <option key={o.id} value={o.id}>{o.label}</option>)}
          </select>
          {draft.mode === 'default' && mainChanged && (
            <p className="text-xs text-slate-500 mt-1.5">Shown for the saved main provider; it is worked out again when you save.</p>
          )}

          {draft.mode === 'custom' && (
            <div className="mt-3 space-y-3">
              {draft.backups.length === 0 && <p className="text-xs text-slate-500">No backups yet. Add one below.</p>}
              {draft.backups.map((b, i) => (
                <div key={i} className="p-3 bg-slate-900/40 border border-white/5 rounded-xl min-w-0">
                  <div className="flex items-center justify-between gap-2 mb-2">
                    <span className="text-xs font-semibold text-slate-400">Backup {i + 1}</span>
                    {writable && (
                      <div className="flex items-center gap-1.5">
                        <button type="button" aria-label="Move up" title="Move up" onClick={() => moveBackup(i, -1)} disabled={busy || i === 0} className={iconBtn}><ArrowUp size={14} /></button>
                        <button type="button" aria-label="Move down" title="Move down" onClick={() => moveBackup(i, 1)} disabled={busy || i === draft.backups.length - 1} className={iconBtn}><ArrowDown size={14} /></button>
                        <button type="button" aria-label="Remove backup" title="Remove" onClick={() => removeBackup(i)} disabled={busy} className={`${iconBtn} text-red-300`}><X size={14} /></button>
                      </div>
                    )}
                  </div>
                  <TargetEditor
                    target={b}
                    onChange={(t) => setBackup(i, t)}
                    allowed={allowed}
                    knownModels={knownModels}
                    configured={configured}
                    label={{ text: `${row.label} backup ${i + 1}` }}
                  />
                </div>
              ))}
              {writable && (
                <button
                  type="button"
                  onClick={addBackup}
                  disabled={busy}
                  className="px-3 py-2 bg-slate-500/15 border border-slate-400/20 rounded-xl text-slate-300 text-sm font-semibold flex items-center gap-2 hover:bg-slate-500/25 disabled:opacity-40"
                >
                  <Plus size={14} /> Add backup
                </button>
              )}
            </div>
          )}
        </div>
      </fieldset>

      {duplicate && (
        <p className="mt-3 text-xs text-amber-300 flex items-start gap-1.5">
          <AlertTriangle size={14} className="flex-shrink-0 mt-px" />
          <span className="break-all">{duplicate} is listed twice. Each provider and model can appear once.</span>
        </p>
      )}

      {writable && (
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            onClick={() => onSave(row.key, toBody(draft))}
            disabled={busy || !canSave}
            className="px-4 py-2.5 bg-blue-500 hover:bg-blue-600 rounded-xl text-white text-sm font-semibold flex items-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {busy ? <RefreshCw size={15} className="animate-spin" /> : <Save size={15} />}
            Save
          </button>
          <button
            onClick={() => onReset(row.key)}
            disabled={busy || row.panel == null}
            title={row.panel == null ? 'No admin-panel setting to remove' : undefined}
            className="px-4 py-2.5 bg-slate-500/15 border border-slate-400/20 rounded-xl text-slate-300 text-sm font-semibold flex items-center gap-2 hover:bg-slate-500/25 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <RotateCcw size={15} /> Use server setting
          </button>
        </div>
      )}

      {message?.errors?.length > 0 && (
        <div role="alert" className="mt-3 p-3 bg-red-500/5 border border-red-500/20 rounded-xl text-xs text-red-300 space-y-1">
          {message.errors.map((e, i) => (
            <div key={i} className="flex items-start gap-1.5 break-words min-w-0">
              <AlertCircle size={14} className="flex-shrink-0 mt-px" />
              <span className="min-w-0 break-words">{e}</span>
            </div>
          ))}
        </div>
      )}
      {message?.notice && (
        <div className="mt-3 p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-xl text-xs text-emerald-300 flex items-start gap-1.5">
          <CheckCircle size={14} className="flex-shrink-0 mt-px" /> {message.notice}
        </div>
      )}
      {message?.warnings?.length > 0 && (
        <div className="mt-3 p-3 bg-amber-500/10 border border-amber-500/20 rounded-xl text-xs text-amber-200 space-y-1">
          {message.warnings.map((w, i) => (
            <div key={i} className="flex items-start gap-1.5 min-w-0">
              <AlertTriangle size={14} className="flex-shrink-0 mt-px" />
              <span className="min-w-0 break-words">{w}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

// ─── Page ─────────────────────────────────────────────────────────────────────
const AISettings = ({ token, adminRole }) => {
  const writable = canWrite(adminRole);
  const [config, setConfig] = useState(null);       // { providers, features }
  const [status, setStatus] = useState(null);       // { providers }
  const [loadError, setLoadError] = useState(null);
  const [statusError, setStatusError] = useState(null);
  const [loading, setLoading] = useState(true);
  const [busyFeature, setBusyFeature] = useState(null);
  const [messages, setMessages] = useState({});     // feature key -> { errors, warnings, notice }
  const [testing, setTesting] = useState(null);     // provider id
  const [testResults, setTestResults] = useState({});

  const loadStatus = useCallback(async () => {
    try {
      const s = await getAIStatus(token);
      setStatus(s);
      setStatusError(null);
    } catch (err) {
      setStatusError(errorMessage(err, 'Could not refresh the provider status'));
    }
  }, [token]);

  const fetchAll = useCallback(async () => {
    try {
      const [c, s] = await Promise.all([getAISettings(token), getAIStatus(token)]);
      setConfig(c);
      setStatus(s);
      setLoadError(null);
      setStatusError(null);
    } catch (err) {
      setLoadError(errorMessage(err, 'Failed to load the AI provider settings'));
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    fetchAll();
  }, [fetchAll]);

  const loadAll = () => {
    setLoading(true);
    fetchAll();
  };

  // Status refreshes every 30 s while the page is open.
  useEffect(() => {
    const id = setInterval(loadStatus, STATUS_REFRESH_MS);
    return () => clearInterval(id);
  }, [loadStatus]);

  const replaceRow = (row) => setConfig((c) => (c ? { ...c, features: c.features.map((f) => (f.key === row.key ? { ...f, ...row } : f)) } : c));
  const setMessage = (key, m) => setMessages((all) => ({ ...all, [key]: m }));

  const handleSave = async (key, body) => {
    setBusyFeature(key);
    setMessage(key, null);
    try {
      const res = await updateAISetting(token, key, body);
      const { warnings, ...row } = res;
      replaceRow(row);
      setMessage(key, { notice: 'Saved.', warnings: Array.isArray(warnings) ? warnings : [] });
    } catch (err) {
      setMessage(key, { errors: errorLines(err) });
    } finally {
      setBusyFeature(null);
    }
  };

  const handleReset = async (key) => {
    setBusyFeature(key);
    setMessage(key, null);
    try {
      replaceRow(await resetAISetting(token, key));
      setMessage(key, { notice: 'Now using the server setting.' });
    } catch (err) {
      setMessage(key, { errors: errorLines(err) });
    } finally {
      setBusyFeature(null);
    }
  };

  const handleTest = async (provider) => {
    setTesting(provider);
    setTestResults((r) => ({ ...r, [provider]: null }));
    try {
      const res = await testAIProvider(token, provider);
      setTestResults((r) => ({ ...r, [provider]: res?.ok ? { ok: true } : { ok: false, error: res?.error || 'unknown error' } }));
    } catch (err) {
      setTestResults((r) => ({ ...r, [provider]: { ok: false, error: errorMessage(err, 'Request failed') } }));
    } finally {
      setTesting(null);
      loadStatus();
    }
  };

  if (loading && !config) {
    return <div className="flex items-center justify-center p-20"><RefreshCw size={32} className="animate-spin text-blue-500" /></div>;
  }

  const statusById = Object.fromEntries((status?.providers ?? []).map((p) => [p.id, p]));

  return (
    <div className="animate-slideIn">
      <div className="mb-8 mt-2 md:mt-0 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            AI Providers
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            {writable
              ? 'Choose the provider and model for each AI feature, and watch how the providers are doing'
              : 'Which provider and model each AI feature uses, and how the providers are doing (read-only)'}
          </p>
        </div>
        <button
          onClick={loadAll}
          title="Reload"
          aria-label="Reload"
          className="p-3 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 hover:bg-slate-500/30 flex-shrink-0"
        >
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {loadError && (
        <div className="p-6 bg-red-500/5 border border-red-500/20 rounded-2xl flex flex-col md:flex-row items-start md:items-center gap-4 mb-6">
          <AlertCircle size={22} className="text-red-400 flex-shrink-0" />
          <div className="flex-1 text-sm text-red-300">{loadError}</div>
          <button onClick={loadAll} className="px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-300 text-sm font-semibold hover:bg-red-500/25 flex items-center gap-2">
            <RefreshCw size={14} /> Retry
          </button>
        </div>
      )}

      {config && (
        <>
          <div className="flex items-center gap-2 mb-4">
            <Bot size={20} className="text-blue-400" />
            <h2 className="text-xl font-bold text-slate-100">Provider status</h2>
          </div>
          {statusError && <div className="mb-4 text-xs text-amber-300">{statusError}. Showing the last known status.</div>}
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 mb-10">
            {config.providers.map((p) => (
              <StatusCard
                key={p.id}
                provider={p}
                status={statusById[p.id]}
                writable={writable}
                testing={testing === p.id}
                testResult={testResults[p.id]}
                onTest={handleTest}
              />
            ))}
          </div>

          <h2 className="text-xl font-bold text-slate-100 mb-1">Features</h2>
          <p className="text-slate-400 text-sm mb-4">
            If the main provider fails, the backups are tried in order. A provider with no API key on the server is skipped.
          </p>
          <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
            {config.features.map((row) => (
              <FeatureCard
                // Start from the new values whenever the server's row changes (after a save or reset).
                key={`${row.key}|${JSON.stringify(row.effective)}`}
                row={row}
                providers={config.providers}
                knownModels={row.known_models ?? {}}
                writable={writable}
                busy={busyFeature === row.key}
                message={messages[row.key]}
                onSave={handleSave}
                onReset={handleReset}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default AISettings;
