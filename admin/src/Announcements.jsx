import { useState, useEffect, useCallback } from 'react';
import { RefreshCw, AlertCircle, Megaphone, Plus, Edit2, Trash2, Save } from 'lucide-react';
import { apiRequest, errorMessage } from './api';
import { PLANS, planLabel } from './planLabels';
import {
  card, field, isoToLocalInput, localInputToIso, errorLines,
} from './appControlShared';
import { ErrorBox, NoticeBox, Counter } from './AppControlParts';

const MAX_TEXT = 500;
const MAX_LINK = 500;
const MAX_LABEL = 40;
const BASE = '/api/admin/app-control/announcements';

const emptyForm = () => ({
  id: null, textEn: '', textMy: '', style: 'info', linkUrl: '', labelEn: '', labelMy: '',
  plans: [...PLANS], startsAt: isoToLocalInput(new Date().toISOString()), endsAt: '',
});

const toForm = (a) => ({
  id: a.id, textEn: a.text_en, textMy: a.text_my, style: a.style, linkUrl: a.link_url ?? '',
  labelEn: a.link_label_en ?? '', labelMy: a.link_label_my ?? '', plans: [...a.plans],
  startsAt: isoToLocalInput(a.starts_at), endsAt: isoToLocalInput(a.ends_at),
});

const toBody = (f) => ({
  text_en: f.textEn.trim(), text_my: f.textMy.trim(), style: f.style,
  link_url: f.linkUrl.trim() || null, link_label_en: f.labelEn.trim() || null, link_label_my: f.labelMy.trim() || null,
  plans: f.plans, starts_at: localInputToIso(f.startsAt), ends_at: localInputToIso(f.endsAt),
});

const fmtWhen = (iso) => (iso ? new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : 'no end');

const statusOf = (a, now) => {
  if (new Date(a.starts_at) > now) return 'scheduled';
  if (a.ends_at && new Date(a.ends_at) <= now) return 'ended';
  return 'live';
};
const SECTIONS = [['live', 'Live'], ['scheduled', 'Scheduled'], ['ended', 'Ended']];

const STYLE_BOX = {
  info: 'bg-blue-500/10 border-blue-500/30 text-blue-100',
  warning: 'bg-amber-500/10 border-amber-500/30 text-amber-100',
};

/** One announcement as the app shows it in one language. */
const BannerPreview = ({ lang, style, text, linkUrl, label }) => (
  <div className={`p-3 rounded-xl border text-sm ${STYLE_BOX[style] ?? STYLE_BOX.info}`}>
    <div className="text-[10px] font-semibold uppercase tracking-wider opacity-60 mb-1">{lang === 'en' ? 'English' : 'Myanmar'}</div>
    <div lang={lang} className="break-words whitespace-pre-wrap">{text || '…'}</div>
    {linkUrl && <div className="mt-1.5 text-xs font-semibold underline">{label || 'Open'}</div>}
  </div>
);

const Row = ({ a, status, writable, onEdit, onDelete }) => (
  <div className="p-4 border-b border-white/5 last:border-b-0">
    <div className="flex items-start justify-between gap-3 mb-3">
      <div className="min-w-0 text-xs text-slate-400">
        <span className="font-semibold text-slate-300">{fmtWhen(a.starts_at)}</span> to <span className="font-semibold text-slate-300">{fmtWhen(a.ends_at)}</span>
        {' · '}{a.style}{' · '}{a.plans.map(planLabel).join(', ')}
        {status === 'live' && <span className="ml-2 text-emerald-300 font-semibold">Live now</span>}
      </div>
      {writable && (
        <div className="flex gap-2 flex-shrink-0">
          <button onClick={() => onEdit(a)} aria-label="Edit announcement" title="Edit"
            className="p-2 bg-blue-500/15 border border-blue-500/25 rounded-lg text-blue-300 hover:bg-blue-500/25"><Edit2 size={14} /></button>
          <button onClick={() => onDelete(a)} aria-label="Delete announcement" title="Delete"
            className="p-2 bg-red-500/15 border border-red-500/25 rounded-lg text-red-300 hover:bg-red-500/25"><Trash2 size={14} /></button>
        </div>
      )}
    </div>
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
      <BannerPreview lang="en" style={a.style} text={a.text_en} linkUrl={a.link_url} label={a.link_label_en} />
      <BannerPreview lang="my" style={a.style} text={a.text_my} linkUrl={a.link_url} label={a.link_label_my} />
    </div>
  </div>
);

const Announcements = ({ token, writable, ...props }) => {
  const { ConfirmDialog } = props; // the page's in-page confirm dialog
  const [items, setItems] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [form, setForm] = useState(null);          // the create/edit form, or null
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);    // { errors, notice } for the page
  const [formErrors, setFormErrors] = useState(null);
  const [deleting, setDeleting] = useState(null);

  const load = useCallback(async () => {
    try {
      setItems(await apiRequest(BASE, { token }));
      setLoadError(null);
    } catch (err) {
      setLoadError(errorMessage(err, 'Failed to load announcements'));
    }
  }, [token]);

  useEffect(() => {
    load();
  }, [load]);

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));
  const togglePlan = (plan) => setForm((f) => ({
    ...f, plans: f.plans.includes(plan) ? f.plans.filter((p) => p !== plan) : [...f.plans, plan],
  }));

  const submit = async () => {
    setBusy(true);
    setFormErrors(null);
    setMessage(null);
    try {
      const body = toBody(form);
      if (form.id) await apiRequest(`${BASE}/${encodeURIComponent(form.id)}`, { token, method: 'PUT', body });
      else await apiRequest(BASE, { token, method: 'POST', body });
      setMessage({ notice: form.id ? 'Announcement updated.' : 'Announcement created.' });
      setForm(null);
      await load();
    } catch (err) {
      setFormErrors(errorLines(err));
    } finally {
      setBusy(false);
    }
  };

  const confirmDelete = async () => {
    setBusy(true);
    setMessage(null);
    try {
      await apiRequest(`${BASE}/${encodeURIComponent(deleting.id)}`, { token, method: 'DELETE' });
      setMessage({ notice: 'Announcement deleted.' });
      setDeleting(null);
      await load();
    } catch (err) {
      setDeleting(null);
      setMessage({ errors: errorLines(err) });
    } finally {
      setBusy(false);
    }
  };

  const now = new Date();
  const formValid = form && form.textEn.trim() && form.textMy.trim() && form.plans.length > 0 && form.startsAt
    && form.textEn.length <= MAX_TEXT && form.textMy.length <= MAX_TEXT;

  return (
    <div className="mb-6">
      <div className="flex items-center justify-between gap-3 mb-1">
        <div className="flex items-center gap-2">
          <Megaphone size={20} className="text-blue-400" />
          <h2 className="text-xl font-bold text-slate-100">Announcements</h2>
        </div>
        {writable && !form && (
          <button onClick={() => { setForm(emptyForm()); setFormErrors(null); setMessage(null); }}
            className="px-4 py-2 bg-blue-500 hover:bg-blue-600 rounded-xl text-white text-sm font-semibold flex items-center gap-2">
            <Plus size={15} /> New announcement
          </button>
        )}
      </div>
      <p className="text-slate-400 text-sm mb-4">
        A banner signed-in users see in the app during its time window. If several are live, the newest one shows. Changes apply within about a minute.
      </p>

      <ErrorBox lines={message?.errors} />
      <NoticeBox text={message?.notice} />

      {loadError && (
        <div className="p-4 mb-4 bg-red-500/5 border border-red-500/20 rounded-2xl flex items-center gap-3 text-sm text-red-300">
          <AlertCircle size={18} className="flex-shrink-0" />
          <span className="flex-1">{loadError}</span>
          <button onClick={load} className="px-3 py-1.5 bg-red-500/15 border border-red-500/30 rounded-lg text-xs font-semibold flex items-center gap-1.5"><RefreshCw size={12} /> Retry</button>
        </div>
      )}

      {form && (
        <fieldset disabled={busy} className={`${card} p-5 mb-6 border-0 min-w-0`}>
          <h3 className="text-base font-bold text-slate-100 mb-4">{form.id ? 'Edit announcement' : 'New announcement'}</h3>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
            <div className="min-w-0">
              <label htmlFor="ann-text-en" className="block text-xs font-semibold text-slate-400 mb-1.5">English text</label>
              <textarea id="ann-text-en" lang="en" rows={3} value={form.textEn} onChange={(e) => set({ textEn: e.target.value })} className={`${field} resize-y`} />
              <Counter value={form.textEn} max={MAX_TEXT} />
            </div>
            <div className="min-w-0">
              <label htmlFor="ann-text-my" className="block text-xs font-semibold text-slate-400 mb-1.5">Myanmar text</label>
              <textarea id="ann-text-my" lang="my" rows={3} value={form.textMy} onChange={(e) => set({ textMy: e.target.value })} className={`${field} resize-y`} />
              <Counter value={form.textMy} max={MAX_TEXT} />
            </div>
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
            <div className="min-w-0">
              <label htmlFor="ann-style" className="block text-xs font-semibold text-slate-400 mb-1.5">Style</label>
              <select id="ann-style" value={form.style} onChange={(e) => set({ style: e.target.value })} className={field}>
                <option value="info">Info</option>
                <option value="warning">Warning</option>
              </select>
            </div>
            <div className="min-w-0">
              <label htmlFor="ann-start" className="block text-xs font-semibold text-slate-400 mb-1.5">Starts (your local time)</label>
              <input id="ann-start" type="datetime-local" value={form.startsAt} onChange={(e) => set({ startsAt: e.target.value })} className={field} />
            </div>
            <div className="min-w-0">
              <label htmlFor="ann-end" className="block text-xs font-semibold text-slate-400 mb-1.5">Ends (optional)</label>
              <input id="ann-end" type="datetime-local" value={form.endsAt} onChange={(e) => set({ endsAt: e.target.value })} className={field} />
            </div>
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
            <div className="min-w-0">
              <label htmlFor="ann-link" className="block text-xs font-semibold text-slate-400 mb-1.5">Link (optional, http or https)</label>
              <input id="ann-link" type="url" maxLength={MAX_LINK} value={form.linkUrl} placeholder="https://" onChange={(e) => set({ linkUrl: e.target.value })} className={field} />
            </div>
            <div className="min-w-0">
              <label htmlFor="ann-label-en" className="block text-xs font-semibold text-slate-400 mb-1.5">English link label</label>
              <input id="ann-label-en" type="text" lang="en" maxLength={MAX_LABEL} value={form.labelEn} placeholder="Open" onChange={(e) => set({ labelEn: e.target.value })} className={field} />
            </div>
            <div className="min-w-0">
              <label htmlFor="ann-label-my" className="block text-xs font-semibold text-slate-400 mb-1.5">Myanmar link label</label>
              <input id="ann-label-my" type="text" lang="my" maxLength={MAX_LABEL} value={form.labelMy} placeholder="Open" onChange={(e) => set({ labelMy: e.target.value })} className={field} />
            </div>
          </div>
          <div className="mb-4">
            <div className="text-xs font-semibold text-slate-400 mb-1.5">Shown to these plans</div>
            <div className="flex flex-wrap gap-4">
              {PLANS.map((plan) => (
                <label key={plan} className="flex items-center gap-2 text-sm text-slate-200">
                  <input type="checkbox" checked={form.plans.includes(plan)} onChange={() => togglePlan(plan)} className="w-4 h-4" />
                  {planLabel(plan)}
                </label>
              ))}
            </div>
          </div>
          <div className="text-xs font-semibold text-slate-400 mb-1.5">Preview</div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-3 mb-4">
            <BannerPreview lang="en" style={form.style} text={form.textEn} linkUrl={form.linkUrl} label={form.labelEn} />
            <BannerPreview lang="my" style={form.style} text={form.textMy} linkUrl={form.linkUrl} label={form.labelMy} />
          </div>
          <ErrorBox lines={formErrors} />
          <div className="flex flex-wrap gap-3">
            <button onClick={submit} disabled={busy || !formValid}
              className="px-5 py-2.5 bg-blue-500 hover:bg-blue-600 rounded-xl text-white text-sm font-semibold flex items-center gap-2 disabled:opacity-40 disabled:cursor-not-allowed">
              {busy ? <RefreshCw size={15} className="animate-spin" /> : <Save size={15} />}
              {form.id ? 'Save announcement' : 'Create announcement'}
            </button>
            <button onClick={() => setForm(null)} disabled={busy}
              className="px-5 py-2.5 bg-slate-500/20 border border-slate-500/30 rounded-xl text-slate-300 text-sm font-semibold hover:bg-slate-500/30">
              Cancel
            </button>
          </div>
        </fieldset>
      )}

      {items && items.length === 0 && <p className="text-sm text-slate-500">No announcements yet.</p>}
      {items && SECTIONS.map(([status, title]) => {
        const rows = items.filter((a) => statusOf(a, now) === status);
        if (rows.length === 0) return null;
        return (
          <div key={status} className="mb-6">
            <h3 className="text-base font-bold text-slate-200 mb-2">{title} <span className="text-slate-500 font-normal">({rows.length})</span></h3>
            <div className={`${card} overflow-hidden`}>
              {rows.map((a) => <Row key={a.id} a={a} status={status} writable={writable} onEdit={(x) => { setForm(toForm(x)); setFormErrors(null); setMessage(null); }} onDelete={setDeleting} />)}
            </div>
          </div>
        );
      })}

      {deleting && (
        <ConfirmDialog
          title="Delete this announcement?"
          confirmLabel="Delete"
          busy={busy}
          onCancel={() => setDeleting(null)}
          onConfirm={confirmDelete}
          message={<p className="break-words">&ldquo;{deleting.text_en}&rdquo; will be removed for good.</p>}
        />
      )}
    </div>
  );
};

export default Announcements;
