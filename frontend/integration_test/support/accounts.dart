// Local throwaway test accounts created by the E2E seed script (seed_rich.py)
// on the local test backend only. Not real credentials.
class Account {
  final String key;
  final String name;
  final String email;
  final String password;

  /// The plan the seed gives the account: 'free', 'plus' or 'pro'.
  final String plan;
  final String language;
  const Account(this.key, this.name, this.email, this.password,
      {this.plan = 'free', this.language = 'en'});
}

/// Plus: the main account, with a year of rich data and stored insights.
const plus = Account('plus', 'Maya Plus', 'maya@example.com', 'MayaPass123', plan: 'plus');

/// Free: general-purpose Free account. The trial-claim flow upgrades it, so
/// flows that need it Free must run before group 12.
const free = Account('free', 'Felix Free', 'felix@example.com', 'FelixPass123');

/// Pro, with the same data as Plus. The Advanced-chat flow uses up its
/// Advanced allowance, so no other flow may rely on it.
const pro = Account('pro', 'Priya Pro', 'priya@example.com', 'PriyaPass123', plan: 'pro');

/// A Free account that exists only for the chat-limit flow: it sends all of
/// the week's 5 messages, so nothing else may use its chat allowance.
const freeLimit = Account('freelimit', 'Frida Free', 'frida@example.com', 'FridaPass123');

const myanmar = Account('myanmar', 'Aung Myanmar', 'aung@example.com', 'AungPass123',
    plan: 'plus', language: 'my');
const empty = Account('empty', 'Nina New', 'nina@example.com', 'NinaPass123');
const deleteme = Account('deleteme', 'Dee Delete', 'dee@example.com', 'DeePass1234');
