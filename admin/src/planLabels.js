// Plan and feature names shared by the Plans page and the per-user usage panel.
// Keys match the backend catalogue (backend/plans/catalog.py).

export const PLANS = ['free', 'plus', 'pro'];
export const MODES = ['locked', 'included', 'counted'];
export const PERIODS = ['week', 'month'];

export const PLAN_LABELS = { free: 'Free', plus: 'Plus', pro: 'Pro' };

export const FEATURES = [
  'chat', 'chat_advanced', 'insight_monthly', 'insight_weekly', 'insight_translation',
  'insight_custom', 'entry', 'budget_suggestion', 'reports',
];

export const FEATURE_LABELS = {
  chat: 'Chat',
  chat_advanced: 'Advanced chat',
  insight_monthly: 'Monthly insight',
  insight_weekly: 'Weekly insight',
  insight_translation: 'Insight translation',
  insight_custom: 'Custom insight',
  entry: 'AI entries',
  budget_suggestion: 'Budget suggestions',
  reports: 'Reports',
};

// Badge colours per plan (Tailwind classes), shared by the users list and the upgrade requests list.
export const PLAN_BADGE = {
  free: 'bg-slate-500/15 border-slate-500/30 text-slate-400',
  plus: 'bg-amber-500/15 border-amber-500/30 text-amber-500',
  pro: 'bg-violet-500/15 border-violet-500/30 text-violet-400',
};

export const planLabel = (plan) => PLAN_LABELS[plan] ?? String(plan);
export const featureLabel = (feature) => FEATURE_LABELS[feature] ?? String(feature);
