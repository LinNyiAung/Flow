import { useState, useEffect } from 'react';
import { ArrowUpCircle, Crown, Check, X, Eye, RefreshCw } from 'lucide-react';
import { getUpgradeRequests, markUpgradeRequestDone, dismissUpgradeRequest, errorMessage, canWrite, ApiError } from './api';
import { PLAN_BADGE, planLabel } from './planLabels';

const STATUSES = [
  { value: 'pending', label: 'Pending' },
  { value: 'done', label: 'Done' },
  { value: 'dismissed', label: 'Dismissed' },
];

const STATUS_PILL = {
  pending: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
  done: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  dismissed: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
};

// What to contact the user with: the Viber number they gave, otherwise the email of their account.
const viberLink = (number) => `viber://chat?number=${encodeURIComponent(number)}`;

// The price the user picked in the app; nothing when the plan had no price.
const BILLING_LABELS = { month: 'Monthly', year: 'Yearly' };

const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '');

const PlanBadge = ({ plan }) => (
  <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-semibold border ${PLAN_BADGE[plan] ?? PLAN_BADGE.free}`}>
    {plan !== 'free' && <Crown size={12} />}
    {planLabel(plan)}
  </span>
);

/**
 * Users' requests to be moved to Plus or Pro. Moderators can view and open the user; admins can also mark a request
 * done or dismiss it. Setting the user's plan (user detail) marks the request done by itself.
 *
 * onOpenUser(userId): show that user's detail panel. onChanged(): a request was handled (the sidebar count changes).
 * refreshSignal: the dashboard's refresh counter. The list reloads whenever it changes, because a plan change or a
 * user delete from the user panel can answer or remove a request.
 */
const UpgradeRequests = ({ token, adminRole, onOpenUser, onChanged, refreshSignal = 0 }) => {
  const [status, setStatus] = useState('pending');
  const [refreshKey, setRefreshKey] = useState(0);
  const [list, setList] = useState({ key: null, items: [], error: null });
  const [busyId, setBusyId] = useState(null);
  const [notice, setNotice] = useState(null);

  const writable = canWrite(adminRole);
  const queryKey = `${status}|${refreshKey}|${refreshSignal}`;
  const loading = list.key !== queryKey;

  useEffect(() => {
    let cancelled = false;
    getUpgradeRequests(token, { status, limit: 200 })
      .then((data) => {
        if (!cancelled) setList({ key: queryKey, items: Array.isArray(data) ? data : [], error: null });
      })
      .catch((err) => {
        if (cancelled) return;
        console.error(err);
        setList({ key: queryKey, items: [], error: errorMessage(err, 'Failed to load upgrade requests') });
      });
    return () => { cancelled = true; };
  }, [token, status, queryKey]);

  const refresh = () => setRefreshKey((k) => k + 1);

  const handle = async (item, action) => {
    if (action === 'dismiss' && !window.confirm(`Dismiss ${item.name || item.email}'s request for ${planLabel(item.requested_plan)}? They will be notified that it was closed.`)) return;
    setBusyId(item.id);
    setNotice(null);
    try {
      await (action === 'done' ? markUpgradeRequestDone : dismissUpgradeRequest)(token, item.id);
    } catch (err) {
      // 409: someone else (or a plan change) already handled it. 404: the request or its user is gone.
      // Either way the list is reloaded below and shows what is true now.
      if (err instanceof ApiError && err.status === 409) {
        setNotice('That request was already handled, so the list has been refreshed.');
      } else if (err instanceof ApiError && err.status === 404) {
        setNotice('That request no longer exists, so the list has been refreshed.');
      } else {
        alert(errorMessage(err, 'Failed to update the request'));
      }
    } finally {
      setBusyId(null);
      refresh();
      if (onChanged) onChanged();
    }
  };

  const items = list.items;

  return (
    <div className="animate-slideIn">
      <div className="mb-6 md:mb-8 mt-2 md:mt-0">
        <h1 className="text-3xl md:text-4xl font-bold mb-2 bg-gradient-to-br from-slate-100 to-slate-400 bg-clip-text text-transparent">Upgrade Requests</h1>
        <p className="text-slate-400 font-medium text-sm md:text-base">
          Users asking for Plus or Pro. Set their plan from the user panel, then it is marked done by itself{writable ? '' : ' (read-only)'}.
        </p>
      </div>

      {notice && (
        <div role="status" className="mb-4 px-4 py-3 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-300 text-sm flex items-start justify-between gap-3">
          <span>{notice}</span>
          <button onClick={() => setNotice(null)} aria-label="Dismiss note" className="text-amber-300/70 hover:text-amber-300"><X size={14} /></button>
        </div>
      )}

      <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 p-4 md:p-6 rounded-2xl border border-white/5 mb-6 flex gap-4">
        <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Status"
          className="flex-1 md:flex-none px-4 py-3.5 bg-slate-900/50 border border-slate-600/20 rounded-xl text-slate-100 text-[15px] outline-none cursor-pointer focus:border-blue-500/50">
          {STATUSES.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
        <button onClick={refresh} title="Reload"
          className="px-4 py-3.5 bg-slate-500/20 border border-slate-400/20 rounded-xl text-slate-400 text-[15px] font-semibold flex items-center gap-2 hover:bg-slate-500/30 transition-colors">
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      <div className="bg-gradient-to-br from-slate-800/60 to-slate-700/30 rounded-2xl border border-white/5 overflow-hidden">
        {loading ? (
          <div className="p-16 flex items-center justify-center"><RefreshCw size={28} className="animate-spin text-blue-500" /></div>
        ) : list.error ? (
          <div role="alert" className="p-12 text-center text-red-400">{list.error}</div>
        ) : items.length === 0 ? (
          <div className="p-16 text-center text-slate-400 flex flex-col items-center gap-3">
            <ArrowUpCircle size={28} className="text-slate-500" />
            {status === 'pending' ? 'No pending upgrade requests' : `No ${status} requests`}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full border-collapse min-w-[1000px]">
              <thead>
                <tr className="bg-slate-900/50 border-b border-white/5">
                  {['User', 'Plan', 'Contact', 'Note', status === 'pending' ? 'Requested' : 'Handled', 'Actions'].map((header, i) => (
                    <th key={header} className={`px-6 py-4 text-left text-slate-400 text-xs font-semibold tracking-wider uppercase ${i === 5 ? 'text-center' : ''}`}>{header}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <tr key={item.id} className="border-b border-white/5 hover:bg-slate-800/50 transition-colors align-top">
                    <td className="px-6 py-5">
                      <div className="text-[15px] font-semibold text-slate-100 mb-1">{item.name}</div>
                      <div className="text-xs text-slate-400 break-all">{item.email}</div>
                    </td>
                    <td className="px-6 py-5">
                      <div className="flex items-center gap-2 flex-wrap">
                        <PlanBadge plan={item.current_plan} />
                        {item.is_trial && (
                          <span className="text-xs text-slate-400">{item.trial_ends_at ? `On trial until ${fmtDate(item.trial_ends_at)}` : 'On trial'}</span>
                        )}
                        <span className="text-slate-500">→</span>
                        <PlanBadge plan={item.requested_plan} />
                        {item.is_renewal && (
                          <span
                            className="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-semibold border bg-sky-500/10 text-sky-300 border-sky-500/20"
                            title="The user asks to keep the plan they have: extend its end date on the user's detail panel"
                          >
                            Renewal
                          </span>
                        )}
                        {BILLING_LABELS[item.billing] && (
                          <span className="text-xs font-semibold text-slate-300">{BILLING_LABELS[item.billing]}</span>
                        )}
                      </div>
                    </td>
                    <td className="px-6 py-5 text-sm">
                      {item.viber_number ? (
                        <>
                          <div className="text-xs text-slate-500 mb-0.5">Contact on Viber</div>
                          <a href={viberLink(item.viber_number)} className="text-blue-400 hover:text-blue-300 break-all">{item.viber_number}</a>
                        </>
                      ) : (
                        <>
                          <div className="text-xs text-slate-500 mb-0.5">No Viber number: email them</div>
                          <a href={`mailto:${encodeURIComponent(item.email)}`} className="text-blue-400 hover:text-blue-300 break-all">{item.email}</a>
                        </>
                      )}
                    </td>
                    <td className="px-6 py-5 text-sm text-slate-300 max-w-xs whitespace-pre-wrap break-words">
                      {item.note || <span className="text-slate-500">No note</span>}
                    </td>
                    <td className="px-6 py-5 text-sm text-slate-400">
                      {status === 'pending' ? (
                        fmtDate(item.created_at)
                      ) : (
                        <>
                          <span className={`inline-block text-xs font-medium px-2.5 py-1 rounded-full border capitalize mb-1 ${STATUS_PILL[item.status] ?? STATUS_PILL.pending}`}>{item.status}</span>
                          <div>{fmtDate(item.handled_at)}</div>
                          <div className="text-xs text-slate-500">requested {fmtDate(item.created_at)}</div>
                        </>
                      )}
                    </td>
                    <td className="px-6 py-5">
                      <div className="flex flex-wrap items-center justify-center gap-2">
                        <button onClick={() => onOpenUser && onOpenUser(item.user_id)}
                          className="inline-flex items-center gap-1.5 px-3 py-2 bg-blue-500/15 border border-blue-500/30 rounded-lg text-blue-400 text-[13px] font-semibold hover:bg-blue-500/25 transition-colors">
                          <Eye size={14} /> Open user
                        </button>
                        {writable && item.status === 'pending' && (
                          <>
                            <button onClick={() => handle(item, 'done')} disabled={busyId === item.id}
                              className="inline-flex items-center gap-1.5 px-3 py-2 bg-emerald-500/15 border border-emerald-500/30 rounded-lg text-emerald-400 text-[13px] font-semibold hover:bg-emerald-500/25 transition-colors disabled:opacity-50">
                              <Check size={14} /> Mark done
                            </button>
                            <button onClick={() => handle(item, 'dismiss')} disabled={busyId === item.id}
                              className="inline-flex items-center gap-1.5 px-3 py-2 bg-slate-500/15 border border-slate-500/30 rounded-lg text-slate-300 text-[13px] font-semibold hover:bg-slate-500/25 transition-colors disabled:opacity-50">
                              <X size={14} /> Dismiss
                            </button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
};

export default UpgradeRequests;
