import { useState, useEffect, useCallback, useMemo } from 'react';
import { RefreshCw, AlertCircle, AlertTriangle, CheckCircle, Save, Layers } from 'lucide-react';
import {
  errorMessage, formatErrorDetail, canWrite, ApiError, getPlans, updatePlans,
} from './api';
import {
  PLANS, MODES, PERIODS, FEATURES, planLabel, featureLabel,
} from './planLabels';

const MAX_CONTACT_LENGTH = 500;

const MODE_LABELS = { locked: 'Locked', included: 'Included', counted: 'Counted' };
const PERIOD_LABELS = { week: 'per week', month: 'per month' };

const card = 'bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5';
const field = 'w-full min-w-0 px-3 py-2.5 bg-slate-900/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 disabled:opacity-60 disabled:cursor-not-allowed';
// Below xl each feature is a block with the three plans under it; from xl up it is one table row.
const rowGrid = 'grid-cols-1 lg:grid-cols-3 xl:grid-cols-[minmax(0,200px)_repeat(3,minmax(0,1fr))] gap-3 xl:gap-4';

// ─── Draft helpers ────────────────────────────────────────────────────────────
// Quota and cost cap are kept as text while typing and checked/converted when saving.
const toDraft = (data) => ({
  plans: Object.fromEntries(PLANS.map((plan) => {
    const p = data.plans[plan];
    return [plan, {
      limits: Object.fromEntries(Object.entries(p.limits).map(([feature, lim]) => [feature, {
        mode: lim.mode,
        quota: lim.quota == null ? '' : String(lim.quota),
        period: lim.period ?? 'month',
      }])),
      cost: String(p.cost_cap_usd),
    }];
  })),
  contact: { en: data.upgrade_contact?.en ?? '', my: data.upgrade_contact?.my ?? '' },
  owner: { email: data.owner_contact?.email ?? '', viber: data.owner_contact?.viber ?? '' },
});

const toBody = (draft) => ({
  plans: Object.fromEntries(PLANS.map((plan) => {
    const p = draft.plans[plan];
    return [plan, {
      limits: Object.fromEntries(Object.entries(p.limits).map(([feature, lim]) => [feature,
        lim.mode === 'counted'
          ? { mode: 'counted', quota: Number(lim.quota), period: lim.period }
          : { mode: lim.mode, quota: null, period: null }])),
      cost_cap_usd: Number(p.cost),
    }];
  })),
  upgrade_contact: { en: draft.contact.en, my: draft.contact.my },
  owner_contact: { email: draft.owner.email.trim(), viber: draft.owner.viber.trim() },
});

// The same rules as the server (plans/contact.py), so a typo is caught before saving. The server's 422 stays the source of truth.
const validEmail = (text) => !text.trim() || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(text.trim());
const validViber = (text) => {
  const digits = text.replace(/[\s\-.()]/g, '');
  if (!digits) return true;
  return /^\+[0-9]{8,15}$/.test(digits.startsWith('09') ? `+95${digits.slice(1)}` : digits);
};

const validCost = (text) => /^\d+(\.\d+)?$/.test(text.trim()) && Number(text) <= 999999;

/** Problems the form can see before asking the server (the server's 422 stays the source of truth). */
const findProblems = (draft, features) => {
  const out = [];
  for (const plan of PLANS) {
    const p = draft.plans[plan];
    for (const feature of features) {
      const lim = p.limits[feature];
      if (lim.mode === 'counted' && !/^\d+$/.test(lim.quota)) {
        out.push(`${planLabel(plan)} · ${featureLabel(feature)}: enter a quota (a whole number, 0 or more)`);
      }
    }
    if (p.limits.chat?.mode === 'locked' && p.limits.chat_advanced && p.limits.chat_advanced.mode !== 'locked') {
      out.push(`${planLabel(plan)} · ${featureLabel('chat_advanced')}: can only be available when Chat is not locked`);
    }
    if (!validCost(p.cost)) out.push(`${planLabel(plan)}: the cost cap must be an amount in USD from 0 to 999999`);
  }
  if (!validEmail(draft.owner.email)) out.push('Your email: enter a valid email address');
  if (!validViber(draft.owner.viber)) {
    out.push('Your Viber number: enter it with the country code, like +959123456789 (or 09 123 456 789)');
  }
  return out;
};

/** 422 detail: one string (value errors joined by "; ") or FastAPI's list of error dicts. One readable line each. */
const errorLines = (err) => {
  if (err instanceof ApiError && err.status === 422) {
    const d = err.detail;
    if (Array.isArray(d)) {
      const lines = d.map((x) => formatErrorDetail([x], '')).filter(Boolean);
      if (lines.length) return lines;
    }
    if (typeof d === 'string') return d.split('; ').map((s) => s.trim()).filter(Boolean);
    return [formatErrorDetail(d, err.message)];
  }
  return [errorMessage(err, 'Request failed')];
};

// ─── Cells ────────────────────────────────────────────────────────────────────
const LimitCell = ({ plan, feature, lim, chatLocked, onChange }) => {
  const label = `${planLabel(plan)} ${featureLabel(feature)}`;
  const advancedBlocked = feature === 'chat_advanced' && chatLocked && lim.mode !== 'locked';
  // The server never translates insights for Free, so this cell is always Locked.
  const alwaysLocked = plan === 'free' && feature === 'insight_translation';
  return (
    <div className="min-w-0">
      <div className="xl:hidden text-xs font-semibold text-slate-400 uppercase mb-1.5">{planLabel(plan)}</div>
      <div className="grid grid-cols-1 gap-2 min-w-0">
        <select
          aria-label={`${label} mode`}
          value={alwaysLocked ? 'locked' : lim.mode}
          disabled={alwaysLocked}
          onChange={(e) => onChange({ ...lim, mode: e.target.value })}
          className={field}
        >
          {MODES.map((m) => (
            <option key={m} value={m} disabled={feature === 'chat_advanced' && chatLocked && m !== 'locked'}>{MODE_LABELS[m]}</option>
          ))}
        </select>
        {lim.mode === 'counted' && (
          <div className="grid grid-cols-[minmax(0,5rem)_minmax(0,1fr)] gap-2 min-w-0">
            <input
              type="text"
              inputMode="numeric"
              aria-label={`${label} quota`}
              value={lim.quota}
              maxLength={10}
              placeholder="0"
              onChange={(e) => onChange({ ...lim, quota: e.target.value.replace(/\D/g, '') })}
              className={field}
            />
            <select
              aria-label={`${label} period`}
              value={lim.period}
              onChange={(e) => onChange({ ...lim, period: e.target.value })}
              className={field}
            >
              {PERIODS.map((p) => <option key={p} value={p}>{PERIOD_LABELS[p]}</option>)}
            </select>
          </div>
        )}
      </div>
      {alwaysLocked && <p className="mt-1.5 text-xs text-slate-500">Always locked: Free never gets translated insights.</p>}
      {advancedBlocked && (
        <p className="mt-1.5 text-xs text-amber-300 flex items-start gap-1.5">
          <AlertTriangle size={13} className="flex-shrink-0 mt-px" />
          <span>Needs Chat to be available.</span>
        </p>
      )}
    </div>
  );
};

const ContactField = ({ id, label, value, disabled, lang, onChange }) => (
  <div className="min-w-0">
    <label htmlFor={id} className="block text-sm font-semibold text-slate-300 mb-2">{label}</label>
    <textarea
      id={id}
      lang={lang}
      rows={4}
      value={value}
      maxLength={MAX_CONTACT_LENGTH}
      disabled={disabled}
      onChange={(e) => onChange(e.target.value)}
      className={`${field} resize-y`}
    />
    <div className="text-xs text-slate-500 mt-1.5">{value.length}/{MAX_CONTACT_LENGTH} characters</div>
  </div>
);

const OwnerField = ({ id, label, type, placeholder, hint, maxLength, value, disabled, onChange }) => (
  <div className="min-w-0">
    <label htmlFor={id} className="block text-sm font-semibold text-slate-300 mb-2">{label}</label>
    <input
      id={id}
      type={type}
      value={value}
      placeholder={placeholder}
      maxLength={maxLength}
      disabled={disabled}
      onChange={(e) => onChange(e.target.value)}
      className={field}
    />
    {hint && <div className="text-xs text-slate-500 mt-1.5">{hint}</div>}
  </div>
);

// ─── Page ─────────────────────────────────────────────────────────────────────
const PlansSettings = ({ token, adminRole }) => {
  const writable = canWrite(adminRole);
  const [saved, setSaved] = useState(null);       // last data from the server
  const [draft, setDraft] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);   // { errors, notice }

  const fetchPlans = useCallback(async () => {
    try {
      const data = await getPlans(token);
      setSaved(data);
      setDraft(toDraft(data));
      setLoadError(null);
    } catch (err) {
      setLoadError(errorMessage(err, 'Failed to load the plans'));
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    fetchPlans();
  }, [fetchPlans]);

  const reload = () => {
    setLoading(true);
    setMessage(null);
    fetchPlans();
  };

  // Features in the catalogue's order; any the server adds later still show up, so a save never drops one.
  const features = useMemo(() => {
    const keys = Object.keys(saved?.plans?.free?.limits ?? {});
    const rank = (f) => (FEATURES.includes(f) ? FEATURES.indexOf(f) : FEATURES.length);
    return keys.sort((a, b) => rank(a) - rank(b));
  }, [saved]);

  const problems = useMemo(() => (draft ? findProblems(draft, features) : []), [draft, features]);
  const dirty = useMemo(
    () => !!(saved && draft) && JSON.stringify(draft) !== JSON.stringify(toDraft(saved)),
    [saved, draft],
  );

  const setLimit = (plan, feature, lim) => setDraft((d) => ({
    ...d,
    plans: { ...d.plans, [plan]: { ...d.plans[plan], limits: { ...d.plans[plan].limits, [feature]: lim } } },
  }));
  const setCost = (plan, cost) => setDraft((d) => ({ ...d, plans: { ...d.plans, [plan]: { ...d.plans[plan], cost } } }));
  const setContact = (lang, text) => setDraft((d) => ({ ...d, contact: { ...d.contact, [lang]: text } }));
  const setOwner = (key, text) => setDraft((d) => ({ ...d, owner: { ...d.owner, [key]: text } }));

  const handleSave = async () => {
    setBusy(true);
    setMessage(null);
    try {
      const res = await updatePlans(token, toBody(draft));
      setSaved(res);
      setDraft(toDraft(res));
      setMessage({ notice: 'Saved. The app picks up the change within about a minute.' });
    } catch (err) {
      setMessage({ errors: errorLines(err) });
    } finally {
      setBusy(false);
    }
  };

  if (loading && !draft) {
    return <div className="flex items-center justify-center p-20"><RefreshCw size={32} className="animate-spin text-blue-500" /></div>;
  }

  return (
    <div className="animate-slideIn">
      <div className="mb-8 mt-2 md:mt-0 flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">
            Plans
          </h1>
          <p className="text-slate-400 font-medium text-sm md:text-base">
            {writable
              ? 'What each plan includes, how often each AI feature can be used, and the monthly AI cost cap'
              : 'What each plan includes, how often each AI feature can be used, and the monthly AI cost cap (read-only)'}
          </p>
        </div>
        <button
          onClick={reload}
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
          <button onClick={reload} className="px-4 py-2 bg-red-500/15 border border-red-500/30 rounded-lg text-red-300 text-sm font-semibold hover:bg-red-500/25 flex items-center gap-2">
            <RefreshCw size={14} /> Retry
          </button>
        </div>
      )}

      {draft && (
        <>
          <div className="flex items-center gap-2 mb-1">
            <Layers size={20} className="text-blue-400" />
            <h2 className="text-xl font-bold text-slate-100">Limits</h2>
          </div>
          <p className="text-slate-400 text-sm mb-4">
            <strong className="text-slate-300">Locked</strong>: not available.{' '}
            <strong className="text-slate-300">Included</strong>: available with no count.{' '}
            <strong className="text-slate-300">Counted</strong>: a number of uses per week or month.
          </p>

          <fieldset disabled={!writable || busy} className="border-0 p-0 m-0 min-w-0">
            <div className={`${card} overflow-hidden mb-8`}>
              <div className={`hidden xl:grid ${rowGrid} px-5 py-3 bg-slate-900/50 border-b border-white/5 text-xs font-semibold text-slate-400 uppercase tracking-wider`}>
                <div>Feature</div>
                {PLANS.map((p) => <div key={p}>{planLabel(p)}</div>)}
              </div>
              {features.map((feature) => (
                <div key={feature} className={`grid ${rowGrid} p-4 xl:px-5 border-b border-white/5 last:border-b-0`}>
                  <div className="min-w-0 lg:col-span-3 xl:col-span-1 xl:self-center">
                    <div className="text-sm font-bold text-slate-100">{featureLabel(feature)}</div>
                    <div className="text-xs text-slate-500 break-all">{feature}</div>
                  </div>
                  {PLANS.map((plan) => (
                    <LimitCell
                      key={plan}
                      plan={plan}
                      feature={feature}
                      lim={draft.plans[plan].limits[feature]}
                      chatLocked={draft.plans[plan].limits.chat?.mode === 'locked'}
                      onChange={(lim) => setLimit(plan, feature, lim)}
                    />
                  ))}
                </div>
              ))}
              <div className={`grid ${rowGrid} p-4 xl:px-5 bg-slate-900/30`}>
                <div className="min-w-0 lg:col-span-3 xl:col-span-1">
                  <div className="text-sm font-bold text-slate-100">Monthly cost cap</div>
                  <div className="text-xs text-slate-500">AI spend per user (USD). Users never see it.</div>
                </div>
                {PLANS.map((plan) => (
                  <div key={plan} className="min-w-0">
                    <div className="xl:hidden text-xs font-semibold text-slate-400 uppercase mb-1.5">{planLabel(plan)}</div>
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="text-slate-400 text-sm">$</span>
                      <input
                        type="text"
                        inputMode="decimal"
                        aria-label={`${planLabel(plan)} monthly cost cap in USD`}
                        value={draft.plans[plan].cost}
                        onChange={(e) => setCost(plan, e.target.value.replace(/[^\d.]/g, ''))}
                        className={field}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>

            <h2 className="text-xl font-bold text-slate-100 mb-1">Upgrade contact</h2>
            <p className="text-slate-400 text-sm mb-4">
              Shown in the app when a user hits a limit and an upgrade would help: how to reach you to upgrade.
            </p>
            <div className={`${card} p-5 mb-6 grid grid-cols-1 lg:grid-cols-2 gap-4`}>
              <ContactField id="contact-en" label="English" lang="en" value={draft.contact.en} disabled={!writable || busy} onChange={(t) => setContact('en', t)} />
              <ContactField id="contact-my" label="Myanmar" lang="my" value={draft.contact.my} disabled={!writable || busy} onChange={(t) => setContact('my', t)} />
            </div>

            <h2 className="text-xl font-bold text-slate-100 mb-1">Your contact details</h2>
            <p className="text-slate-400 text-sm mb-4">
              Your own email and Viber number. The app shows them next to the message above so users can reach you directly,
              and adds them to the notice a user gets when you close their upgrade request. Leave one empty to hide it.
            </p>
            <div className={`${card} p-5 mb-6 grid grid-cols-1 lg:grid-cols-2 gap-4`}>
              <OwnerField id="owner-email" label="Email" type="email" placeholder="you@example.com" maxLength={254}
                value={draft.owner.email} disabled={!writable || busy} onChange={(t) => setOwner('email', t)} />
              <OwnerField id="owner-viber" label="Viber number" type="tel" placeholder="09 123 456 789" maxLength={30}
                hint="With the country code, like +959123456789. A Myanmar number starting with 09 is converted to +959…"
                value={draft.owner.viber} disabled={!writable || busy} onChange={(t) => setOwner('viber', t)} />
            </div>
          </fieldset>

          {writable && (
            <div className="space-y-3 mb-6">
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
                <button
                  onClick={handleSave}
                  disabled={busy || !dirty || problems.length > 0}
                  className="px-5 py-2.5 bg-blue-500 hover:bg-blue-600 rounded-xl text-white text-sm font-semibold flex items-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  {busy ? <RefreshCw size={15} className="animate-spin" /> : <Save size={15} />}
                  Save
                </button>
                {dirty && !busy && <span className="text-xs text-slate-400">Unsaved changes</span>}
              </div>
            </div>
          )}

          {message?.errors?.length > 0 && (
            <div role="alert" className="mb-6 p-3 bg-red-500/5 border border-red-500/20 rounded-xl text-xs text-red-300 space-y-1">
              {message.errors.map((e, i) => (
                <div key={i} className="flex items-start gap-1.5 min-w-0">
                  <AlertCircle size={14} className="flex-shrink-0 mt-px" />
                  <span className="min-w-0 break-words">{e}</span>
                </div>
              ))}
            </div>
          )}
          {message?.notice && (
            <div className="mb-6 p-3 bg-emerald-500/10 border border-emerald-500/20 rounded-xl text-xs text-emerald-300 flex items-start gap-1.5">
              <CheckCircle size={14} className="flex-shrink-0 mt-px" /> {message.notice}
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default PlansSettings;
