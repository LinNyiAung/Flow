// Plan and feature names shared by the Plans page and the per-user usage panel.
// Keys match the backend catalogue (backend/plans/catalog.py).

export const PLANS = ['free', 'plus', 'pro'];
export const MODES = ['locked', 'included', 'counted'];
export const PERIODS = ['week', 'month'];

export const PLAN_LABELS = { free: 'Free', plus: 'Plus', pro: 'Pro' };

export const FEATURES = [
  'chat', 'chat_advanced', 'insight_monthly', 'insight_weekly', 'insight_translation',
  'entry', 'budget_suggestion', 'reports',
];

export const FEATURE_LABELS = {
  chat: 'Chat',
  chat_advanced: 'Advanced chat',
  insight_monthly: 'Monthly insight',
  insight_weekly: 'Weekly insight',
  insight_translation: 'Insight translation',
  entry: 'AI entries',
  budget_suggestion: 'Budget suggestions',
  reports: 'Reports',
};

export const planLabel = (plan) => PLAN_LABELS[plan] ?? String(plan);
export const featureLabel = (feature) => FEATURE_LABELS[feature] ?? String(feature);
