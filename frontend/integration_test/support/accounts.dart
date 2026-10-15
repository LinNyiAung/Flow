// Local throwaway test accounts created by the E2E seed script (seed_rich.py)
// on the local test backend only. Not real credentials.
class Account {
  final String key;
  final String name;
  final String email;
  final String password;
  final bool premium;
  final String language;
  const Account(this.key, this.name, this.email, this.password,
      {this.premium = false, this.language = 'en'});
}

const premium = Account('premium', 'Maya Premium', 'maya@example.com', 'MayaPass123', premium: true);
const free = Account('free', 'Felix Free', 'felix@example.com', 'FelixPass123');
const myanmar = Account('myanmar', 'Aung Myanmar', 'aung@example.com', 'AungPass123',
    premium: true, language: 'my');
const empty = Account('empty', 'Nina New', 'nina@example.com', 'NinaPass123');
const deleteme = Account('deleteme', 'Dee Delete', 'dee@example.com', 'DeePass1234');
