import { useState } from 'react';
import { createPortal } from 'react-dom';
import { Ban, CheckCircle, LogOut, Mail, KeyRound, Send, Pencil, AlertCircle } from 'lucide-react';
import {
  suspendUser, unsuspendUser, signOutUser, updateUserProfile, changeUserEmail,
  sendUserResetCode, messageUser, errorMessage, canWrite, isSuperAdmin, ApiError,
} from './api';

const EMAIL_REMINDER = 'Only do this after checking who you are talking to (recent entries, budget names, their plan).';
const CURRENCIES = ['usd', 'mmk', 'thb'];
const MESSAGE_TYPES = [
  { value: 'system_broadcast', label: 'System message' },
  { value: 'admin_announcement', label: 'Announcement' },
];
const RESET_REASONS = {
  recent: 'a code was sent a moment ago',
  hourly_limit: 'too many codes were sent in the last hour',
  locked: 'the account is locked after wrong codes',
  suspended: 'the account is suspended',
};

const fmtWhen = (iso) => (iso ? new Date(iso).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' }) : '');

const inputCls = 'w-full px-4 py-3 bg-slate-800/50 border border-slate-600/30 rounded-xl text-slate-100 text-sm outline-none focus:border-blue-500 transition-all';
const btnCls = 'w-full p-3 rounded-xl border text-sm font-semibold flex items-center justify-center gap-2 transition-colors disabled:opacity-40 disabled:cursor-not-allowed';
const neutralBtn = `${btnCls} bg-blue-500/15 border-blue-500/30 text-blue-400 hover:bg-blue-500/25`;
const dangerBtn = `${btnCls} bg-red-500/10 border-red-500/30 text-red-400 hover:bg-red-500/20`;

const Section = ({ title, children }) => (
  <div className="p-4 bg-slate-900/40 rounded-xl border border-white/5 space-y-3">
    <div className="text-slate-300 text-sm font-semibold">{title}</div>
    {children}
  </div>
);

/** The suspension status (everyone) and the actions on a person (admins; the email correction super admins only). */
const UserActions = (props) => {
  const { token, user, adminRole, onChanged } = props;
  const { ConfirmDialog } = props; // the page's in-page confirm dialog
  const writable = canWrite(adminRole);
  const isSuper = isSuperAdmin(adminRole);
  const who = `${user.name || 'This person'} (${user.email})`;
  const detailLoaded = user.suspension !== undefined;
  const suspension = user.suspension || null;

  const [confirm, setConfirm] = useState(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState(null); // { ok, text }
  const [reason, setReason] = useState('');
  const [name, setName] = useState(user.name || '');
  const [currency, setCurrency] = useState(user.default_currency || 'usd');
  const [newEmail, setNewEmail] = useState('');
  const [msgTitle, setMsgTitle] = useState('');
  const [msgBody, setMsgBody] = useState('');
  const [msgType, setMsgType] = useState('system_broadcast');

  const ask = (c) => { setNotice(null); setConfirm(c); };

  // Runs the confirmed action; `after` clears drafts on success. Errors show in the notice line.
  const runConfirmed = async () => {
    const c = confirm;
    if (!c) return;
    setBusy(true);
    try {
      const text = await c.run();
      setNotice({ ok: true, text });
      if (c.after) c.after();
      onChanged();
    } catch (err) {
      setNotice({ ok: false, text: errorMessage(err, 'The action failed') });
      if (err instanceof ApiError && err.status === 409) onChanged(); // the state moved on: show it
    } finally {
      setBusy(false);
      setConfirm(null);
    }
  };

  const doSuspend = () => ask({
    title: 'Suspend this person?',
    message: `${who} cannot sign in until you unsuspend them. They get no notices or AI work meanwhile. Reason: ${reason.trim()}`,
    confirmLabel: 'Suspend',
    tone: 'danger',
    run: async () => { await suspendUser(token, user.id, reason.trim()); return 'Suspended.'; },
    after: () => setReason(''),
  });

  const doUnsuspend = () => ask({
    title: 'Unsuspend this person?',
    message: `${who} will be able to sign in again.`,
    confirmLabel: 'Unsuspend',
    tone: 'warning',
    run: async () => { await unsuspendUser(token, user.id); return 'Unsuspended.'; },
  });

  const doSignOut = () => ask({
    title: 'Sign out everywhere?',
    message: `${who} is signed out on every device and must sign in again.`,
    confirmLabel: 'Sign out everywhere',
    tone: 'warning',
    run: async () => {
      const r = await signOutUser(token, user.id);
      return `Signed out (${r?.devices_removed ?? 0} ${r?.devices_removed === 1 ? 'device' : 'devices'} removed).`;
    },
  });

  const trimmedName = name.trim();
  const profileBody = {};
  if (trimmedName !== (user.name || '')) profileBody.name = trimmedName;
  if (currency !== (user.default_currency || 'usd')) profileBody.default_currency = currency;
  const profileChanged = Object.keys(profileBody).length > 0;
  const nameInvalid = profileBody.name !== undefined && trimmedName.length < 2;

  const doProfile = () => ask({
    title: 'Change this profile?',
    message: `${who}: ${[
      profileBody.name !== undefined && `name to "${profileBody.name}"`,
      profileBody.default_currency && `default currency to ${profileBody.default_currency.toUpperCase()}`,
    ].filter(Boolean).join(' and ')}.`,
    confirmLabel: 'Save changes',
    tone: 'warning',
    run: async () => { await updateUserProfile(token, user.id, profileBody); return 'Profile updated.'; },
  });

  const doResetCode = () => ask({
    title: 'Send a reset code?',
    message: `A password reset code goes by email to ${who}. You never see the code.`,
    confirmLabel: 'Send code',
    tone: 'warning',
    run: async () => {
      try {
        await sendUserResetCode(token, user.id);
      } catch (err) {
        const d = err instanceof ApiError && err.detail && typeof err.detail === 'object' ? err.detail : null;
        if (d && d.code === 'reset_code_not_sent') {
          const why = RESET_REASONS[d.reason] || d.message || 'it was not allowed right now';
          throw new Error(`Not sent: ${why}.${d.retry_at ? ` Try again after ${fmtWhen(d.retry_at)}.` : ''}`);
        }
        throw err;
      }
      return 'Sent.';
    },
  });

  const doMessage = () => ask({
    title: 'Send this message?',
    message: `${who} gets "${msgTitle.trim()}" as a ${MESSAGE_TYPES.find((t) => t.value === msgType).label.toLowerCase()} on their devices.`,
    confirmLabel: 'Send message',
    tone: 'warning',
    run: async () => {
      const r = await messageUser(token, user.id, {
        title: msgTitle.trim(), message: msgBody.trim(), notification_type: msgType,
      });
      return `Message sent to ${r?.devices ?? 0} ${r?.devices === 1 ? 'device' : 'devices'}.`;
    },
    after: () => { setMsgTitle(''); setMsgBody(''); },
  });

  const emailValue = newEmail.trim();
  const doEmail = () => ask({
    title: 'Correct the sign-in email?',
    message: `${who} will sign in with ${emailValue} from now on. ${EMAIL_REMINDER}`,
    confirmLabel: 'Change email',
    tone: 'danger',
    run: async () => { await changeUserEmail(token, user.id, emailValue); return 'Sign-in email changed.'; },
    after: () => setNewEmail(''),
  });

  return (
    <div className="mb-8">
      <h3 className="text-xs font-bold text-slate-400 mb-4 uppercase tracking-wider">Account{writable ? ' actions' : ''}</h3>

      {suspension ? (
        <div className="p-4 bg-red-500/10 border border-red-500/30 rounded-xl mb-4 text-sm">
          <div className="font-semibold text-red-300 flex items-center gap-2"><Ban size={16} />Suspended</div>
          <div className="text-slate-300 mt-1 break-words">Reason: {suspension.reason}</div>
          <div className="text-xs text-slate-400 mt-1">
            {fmtWhen(suspension.at)}{suspension.by_email ? ` by ${suspension.by_email}` : ''}
          </div>
        </div>
      ) : (
        detailLoaded && <div className="text-xs text-slate-500 mb-4">Not suspended.</div>
      )}
      {!detailLoaded && user.suspended && <div className="text-xs text-red-300 mb-4">Suspended (loading details…)</div>}

      {notice && (
        <div role={notice.ok ? 'status' : 'alert'}
          className={`mb-4 p-3 rounded-xl border text-xs flex items-start gap-2 break-words ${notice.ok ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-300' : 'bg-red-500/5 border-red-500/20 text-red-300'}`}>
          {notice.ok ? <CheckCircle size={14} className="flex-shrink-0 mt-px" /> : <AlertCircle size={14} className="flex-shrink-0 mt-px" />}
          <span className="flex-1 min-w-0">{notice.text}</span>
        </div>
      )}

      {writable && detailLoaded && (
        <div className="space-y-3">
          {suspension ? (
            <button onClick={doUnsuspend} disabled={busy} className={neutralBtn}><CheckCircle size={16} />Unsuspend</button>
          ) : (
            <Section title="Suspend">
              <textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} rows={2}
                placeholder="Reason (required, shown to admins only)" aria-label="Suspension reason" className={inputCls} />
              <button onClick={doSuspend} disabled={busy || !reason.trim()} className={dangerBtn}><Ban size={16} />Suspend</button>
            </Section>
          )}

          <button onClick={doSignOut} disabled={busy} className={neutralBtn}><LogOut size={16} />Sign out everywhere</button>

          <Section title="Edit profile">
            <input type="text" value={name} onChange={(e) => setName(e.target.value)} maxLength={100}
              aria-label="Name" placeholder="Name" className={inputCls} />
            <label className="block text-slate-400 text-xs">Default currency</label>
            <select value={currency} onChange={(e) => setCurrency(e.target.value)} aria-label="Default currency" className={inputCls}>
              {CURRENCIES.map((c) => <option key={c} value={c}>{c.toUpperCase()}</option>)}
            </select>
            {nameInvalid && <div className="text-xs text-amber-400">A name needs at least 2 characters.</div>}
            <button onClick={doProfile} disabled={busy || !profileChanged || nameInvalid} className={neutralBtn}><Pencil size={16} />Save changes</button>
          </Section>

          <button onClick={doResetCode} disabled={busy || !!suspension} className={neutralBtn}><KeyRound size={16} />Send reset code</button>
          {suspension && <div className="text-xs text-slate-500">Suspended people get no reset codes.</div>}

          <Section title="Message">
            <input type="text" value={msgTitle} onChange={(e) => setMsgTitle(e.target.value)} maxLength={100}
              aria-label="Message title" placeholder="Title" className={inputCls} />
            <textarea value={msgBody} onChange={(e) => setMsgBody(e.target.value)} maxLength={500} rows={3}
              aria-label="Message text" placeholder="Message" className={inputCls} />
            <select value={msgType} onChange={(e) => setMsgType(e.target.value)} aria-label="Message type" className={inputCls}>
              {MESSAGE_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
            <button onClick={doMessage} disabled={busy || !msgTitle.trim() || !msgBody.trim() || !!suspension} className={neutralBtn}>
              <Send size={16} />Send message
            </button>
            {suspension && <div className="text-xs text-slate-500">Suspended people get no messages.</div>}
          </Section>

          {isSuper && (
            <Section title="Correct sign-in email">
              <div className="text-xs text-amber-400">{EMAIL_REMINDER}</div>
              <input type="email" value={newEmail} onChange={(e) => setNewEmail(e.target.value)}
                aria-label="New sign-in email" placeholder="New email address" className={inputCls} />
              <button onClick={doEmail} disabled={busy || !emailValue} className={dangerBtn}><Mail size={16} />Change email</button>
            </Section>
          )}
        </div>
      )}

      {/* In a portal: the modal around this block is animated, which would otherwise anchor the dialog to it. */}
      {confirm && createPortal(
        <ConfirmDialog
          title={confirm.title}
          message={confirm.message}
          confirmLabel={confirm.confirmLabel}
          tone={confirm.tone}
          busy={busy}
          onConfirm={runConfirmed}
          onCancel={() => setConfirm(null)}
        />,
        document.body,
      )}
    </div>
  );
};

export default UserActions;
