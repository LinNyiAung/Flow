"""Snap AI-extracted category names onto the configured category list.

Pure helpers (no DB / network) so they can be unit-tested directly. The extraction
endpoints use them so that a near-miss category name from the model ("Food & Drinks",
"Lunch") becomes a valid category instead of making batch-create reject the batch.

Matching order (see snap_category):
1. Exact main category (case-insensitive) that is not a catch-all -> trusted; only the
   sub-category is resolved inside it (exact, keyword hint, fuzzy, word overlap, else the
   main's generic sub).
2. Otherwise the sub-category (and the given "main", which models often fill with a
   sub-category name such as "Salary" or "Subscriptions") is looked up across ALL main
   categories of the type before the main is fuzzy-matched: exact sub name, main-as-sub
   name, whole-word keyword hints, fuzzy/word-overlap sub match.
3. Fuzzy main category (generic names like "Income"/"Expenses"/"Other" never anchor here).
4. The type's catch-all ("Other Income" / "Other & Adjustments > Other Expenses").
"""
import difflib
import math
import re
from typing import Dict, List, Optional, Sequence, Tuple

# Per-type catch-all category (matches the defaults in database.initialize_categories).
FALLBACK_CATEGORIES: Dict[str, Tuple[str, str]] = {
    "outflow": ("Other & Adjustments", "Other Expenses"),
    "inflow": ("Other Income", "Other Income"),
}

_TYPE_ALIASES = {
    "inflow": "inflow", "income": "inflow", "credit": "inflow", "in": "inflow",
    "outflow": "outflow", "expense": "outflow", "expenses": "outflow", "debit": "outflow", "out": "outflow",
}

# Main-category names that carry no information: they must not anchor the match to the
# type's catch-all before the sub-category has been considered.
_GENERIC_MAINS = {
    "income", "incomes", "inflow", "inflows", "revenue", "earning", "earnings",
    "expense", "expenses", "outflow", "outflows", "spending", "spendings", "cost", "costs",
    "other", "others", "misc", "miscellaneous", "general", "uncategorized", "uncategorised",
    "unknown", "none", "n/a", "na", "null", "category", "transaction", "transactions",
    "payment", "payments", "purchase", "purchases", "bill", "bills",
    "other income", "other incomes", "other expense", "other expenses",
    "misc income", "misc expense", "misc expenses", "general expense", "general expenses",
}

# Keyword hints (sub-category inference). ASCII keywords match whole words/phrases only
# ("tea" does not match "steak", "train" does not match "training"); non-ASCII (Burmese)
# keywords match as substrings because Burmese text has no spaces between words.
# A hint only applies if its target sub-category exists for the transaction type, so the
# same keyword may appear for an inflow and an outflow target. Order matters: the first
# matching hint wins, so more specific phrases come first.
_SUB_HINTS: Sequence[Tuple[Tuple[str, ...], str]] = (
    # --- inflow ---
    (("tax refund", "tax return"), "Tax Refund"),
    (("reimbursement", "reimbursed", "expense claim"), "Expense Reimbursement"),
    (("cashback", "cash back", "reward", "rewards"), "Cashback / Rewards"),
    (("insurance claim", "insurance payout"), "Insurance Claim"),
    (("refund", "refunds", "refunded", "money back"), "Purchase Refund"),
    (("freelance", "freelancing", "freelancer", "upwork", "fiverr", "gig"), "Freelance Income"),
    (("salary", "salaries", "wage", "wages", "payroll", "paycheck", "paycheque", "pay day", "payday",
      "လစာ"), "Salary"),
    (("overtime", "ot pay"), "Overtime Pay"),
    (("bonus",), "Bonus"),
    (("commission",), "Commission"),
    (("pension",), "Pension"),
    (("side hustle", "side job", "part time", "part-time"), "Side Hustle"),
    (("royalty", "royalties"), "Royalties"),
    (("business income", "sales", "shop income"), "Business Income"),
    (("dividend", "dividends"), "Dividends"),
    (("interest",), "Interest Income"),
    (("rent received", "rental", "tenant"), "Rental Income"),
    (("crypto", "bitcoin"), "Crypto Gains"),
    (("gift", "gifts", "present", "red packet", "angpao", "လက်ဆောင်"), "Gifts Received"),
    (("family support", "from mom", "from dad", "from parents", "allowance from"), "Family Support"),
    (("allowance",), "Allowances"),
    (("lottery", "prize"), "Prize / Lottery"),
    # --- outflow: food ---
    (("bubble tea", "milk tea", "coffee", "tea", "cafe", "café", "latte", "snack", "snacks", "dessert",
      "ကော်ဖီ", "လက်ဖက်ရည်"), "Coffee & Snacks"),
    (("burger", "pizza", "kfc", "mcdonald", "mcdonalds", "mcdonald's", "fast food", "fried chicken"), "Fast Food"),
    (("steak", "dinner", "lunch", "breakfast", "brunch", "meal", "meals", "restaurant", "restaurants",
      "eating out", "eat out", "dine", "dining", "buffet", "noodle", "noodles", "bbq", "hotpot",
      "ထမင်း", "စားသောက်ဆိုင်", "မုန့်ဟင်းခါး"), "Restaurants"),
    (("grocery", "groceries", "supermarket", "market", "vegetable", "vegetables", "fruit", "fruits",
      "ဈေး", "ဟင်းသီးဟင်းရွက်"), "Groceries"),
    (("beer", "wine", "liquor", "alcohol", "whisky", "whiskey", "ဘီယာ"), "Alcohol"),
    # --- outflow: transport ---
    (("fuel", "petrol", "gasoline", "diesel", "gas station", "refuel", "ဓာတ်ဆီ"), "Fuel"),
    (("grab", "taxi", "uber", "cab", "lyft", "ride hailing", "tuk tuk", "တက္ကစီ"), "Taxi"),
    (("bus", "train", "metro", "subway", "mrt", "bts", "ferry", "ybs", "ဘတ်စ်ကား"), "Public Transport"),
    (("parking",), "Parking"),
    (("toll", "tolls", "expressway"), "Toll Fees"),
    (("car repair", "car service", "oil change", "tyre", "tire", "mechanic"), "Vehicle Maintenance"),
    # --- outflow: housing ---
    (("rent", "house rent", "room rent", "အိမ်လခ"), "Rent"),
    (("mortgage", "home loan"), "Mortgage"),
    (("electricity", "electric bill", "power bill", "electricity bill", "မီးဖိုး"), "Electricity"),
    (("water bill", "ရေဖိုး"), "Water"),
    (("internet", "wifi", "wi-fi", "broadband", "fiber", "fibre"), "Internet"),
    (("phone bill", "top up", "top-up", "topup", "phone credit", "mobile data", "ဖုန်းဘေလ်"), "Mobile Phone"),
    # --- outflow: entertainment ---
    (("netflix", "disney+", "disney plus", "hbo", "prime video", "viu", "movie", "movies", "cinema"),
     "Movies & Streaming"),
    (("spotify", "youtube premium", "apple music", "icloud", "subscription", "subscriptions", "membership"),
     "Subscriptions"),
    (("game", "games", "gaming", "steam", "playstation", "xbox"), "Games"),
    (("concert", "concerts", "festival", "event ticket"), "Events & Concerts"),
    # --- outflow: health / education / shopping / travel / finance ---
    (("gym", "fitness", "yoga"), "Fitness & Gym"),
    (("pharmacy", "medicine", "medicines", "drugstore"), "Pharmacy"),
    (("doctor", "clinic", "hospital", "checkup", "check-up"), "Doctor Visits"),
    (("dentist", "dental"), "Dental"),
    (("tuition", "school fee", "school fees", "university fee"), "Tuition Fees"),
    (("udemy", "coursera", "online course", "online courses"), "Online Courses"),
    (("book", "books", "ebook"), "Books"),
    (("clothes", "clothing", "shirt", "t-shirt", "dress", "jeans", "အဝတ်"), "Clothing"),
    (("shoes", "sneakers", "footwear", "slippers"), "Footwear"),
    (("laptop", "headphones", "gadget"), "Electronics"),
    (("flight", "flights", "airfare", "airline", "plane ticket"), "Flights"),
    (("hotel", "airbnb", "hostel", "accommodation"), "Accommodation"),
    (("atm", "cash withdrawal", "withdrawal"), "Cash Withdrawal"),
    (("bank fee", "bank fees", "bank charge", "service charge", "transfer fee"), "Bank Fees"),
    (("loan", "loan repayment", "installment", "instalment"), "Loan Repayment"),
    (("credit card",), "Credit Card Payment"),
    (("interest",), "Interest Paid"),
    (("tax", "taxes"), "Taxes"),
)

_MAIN_CUTOFF = 0.6
_SUB_CUTOFF = 0.6           # fuzzy sub match (inside a main, and across all mains)
_MAIN_AS_SUB_CUTOFF = 0.8   # stricter: the given "main" read as a sub-category name

# Words ignored by word-overlap matching (they appear in many category names).
_STOP_WORDS = {
    "other", "others", "income", "incomes", "expense", "expenses", "and", "from", "with",
    "for", "the", "misc", "miscellaneous", "general", "fees", "payment", "payments",
    "monthly", "weekly", "daily", "yearly", "annual",
}


def normalize_type(tx_type: Optional[str]) -> str:
    """Map model output like "expense"/"Income" onto inflow/outflow (default outflow)."""
    return _TYPE_ALIASES.get((tx_type or "").strip().lower(), "outflow")


def _ci_lookup(value: str, options: Sequence[str]) -> Optional[str]:
    v = (value or "").strip().lower()
    if not v:
        return None
    for o in options:
        if o.lower() == v:
            return o
    return None


def _close(value: str, options: Sequence[str], cutoff: float) -> Optional[str]:
    if not value or not options:
        return None
    lowered = {o.lower(): o for o in options}
    hit = difflib.get_close_matches(value.strip().lower(), list(lowered), n=1, cutoff=cutoff)
    return lowered[hit[0]] if hit else None


def _stem(word: str) -> str:
    """Very light plural stemming so "gifts" ~ "gift", "refunds" ~ "refund"."""
    if len(word) > 4 and word.endswith("ies"):
        return word[:-3] + "y"
    if len(word) > 4 and word.endswith("s") and not word.endswith("ss"):
        return word[:-1]
    return word


def _words(value: str) -> set:
    cleaned = "".join(ch.lower() if ch.isalnum() else " " for ch in (value or ""))
    return {_stem(w) for w in cleaned.split() if len(w) >= 4 and w not in _STOP_WORDS}


def _word_overlap(value: str, options: Sequence[str]) -> Optional[str]:
    """Option sharing the most significant words with value (e.g. "Food" -> "Food & Daily Living")."""
    words = _words(value)
    if not words:
        return None
    best, best_score = None, 0
    for o in options:
        score = len(words & _words(o))
        if score > best_score:
            best, best_score = o, score
    return best


_KEYWORD_RE_CACHE: Dict[str, "re.Pattern"] = {}


def _keyword_in(keyword: str, text_lower: str) -> bool:
    """Whole-word/phrase match for ASCII keywords, substring match for non-ASCII ones."""
    if not keyword.isascii():
        return keyword in text_lower
    pattern = _KEYWORD_RE_CACHE.get(keyword)
    if pattern is None:
        pattern = re.compile(r"(?<![a-z0-9])" + re.escape(keyword) + r"(?![a-z0-9])")
        _KEYWORD_RE_CACHE[keyword] = pattern
    return pattern.search(text_lower) is not None


def _hint(text: str, available: Sequence[str]) -> Optional[str]:
    """Sub-category suggested by a keyword hint in `text`, if that sub exists in `available`."""
    if not text or not available:
        return None
    low = text.strip().lower()
    for keywords, target in _SUB_HINTS:
        hit = _ci_lookup(target, available)
        if hit and any(_keyword_in(k, low) for k in keywords):
            return hit
    return None


def _sub_in_main(sub: str, subs: Sequence[str]) -> Optional[str]:
    """Best sub-category inside one main category: exact, keyword hint, fuzzy, word overlap."""
    if not sub or not subs:
        return None
    return (
        _ci_lookup(sub, subs)
        or _hint(sub, subs)
        or _close(sub, subs, _SUB_CUTOFF)
        or _word_overlap(sub, subs)
    )


def _generic_sub(subs: Sequence[str]) -> Optional[str]:
    """Catch-all sub of a main category ("Other ..."/"Miscellaneous"), else its first sub."""
    for s in subs:
        low = s.lower()
        if "other" in low or "misc" in low:
            return s
    return subs[0] if subs else None


def _is_generic_main(name: str) -> bool:
    low = " ".join((name or "").strip().lower().replace("&", " ").replace("/", " ").split())
    return not low or low in _GENERIC_MAINS


def snap_category(
    tx_type: str,
    main_category: Optional[str],
    sub_category: Optional[str],
    categories: Optional[Dict[str, List[str]]],
) -> Tuple[str, str, bool]:
    """
    Return (main, sub, adjusted) where main/sub are valid for `categories`
    ({main: [subs]} for this transaction type) and adjusted=True if they changed.
    If `categories` is None/empty (not configured), the input is returned unchanged.
    """
    main_in = (main_category or "").strip()
    sub_in = (sub_category or "").strip()
    if not categories:
        return main_in, sub_in, False

    mains = list(categories)

    def result(m: str, s: str) -> Tuple[str, str, bool]:
        return m, s, (m != main_category or s != sub_category)

    def subs_of(m: str) -> List[str]:
        return list(categories.get(m) or [])

    # sub name -> its main (first main wins if a name is used twice)
    sub_owner: Dict[str, str] = {}
    for m in mains:
        for s in subs_of(m):
            sub_owner.setdefault(s, m)
    all_subs = list(sub_owner)

    fb_main_name, fb_sub_name = FALLBACK_CATEGORIES.get(normalize_type(tx_type), FALLBACK_CATEGORIES["outflow"])
    fb_main = _ci_lookup(fb_main_name, mains) or mains[-1]

    generic_main = _is_generic_main(main_in)
    exact_main = _ci_lookup(main_in, mains) if main_in else None

    # 1. A specific exact main is trusted: resolve the sub inside it only.
    if exact_main is not None and exact_main != fb_main and not generic_main:
        subs = subs_of(exact_main)
        if not subs:
            return result(exact_main, sub_in or exact_main)  # main without sub-categories accepts any sub
        return result(exact_main, _sub_in_main(sub_in, subs) or _generic_sub(subs))

    # 2a. Sub-category name found under some main category -> infer the main from it.
    if sub_in:
        hit = _ci_lookup(sub_in, all_subs)
        if hit:
            return result(sub_owner[hit], hit)

    # 2b. The given "main" is really a sub-category name ("Salary", "Subscriptions").
    if main_in and exact_main is None and not generic_main:
        as_sub = _ci_lookup(main_in, all_subs) or _close(main_in, all_subs, _MAIN_AS_SUB_CUTOFF)
        if as_sub:
            owner = sub_owner[as_sub]
            inner = _ci_lookup(sub_in, subs_of(owner)) if sub_in else None
            return result(owner, inner or as_sub)

    # 2c. Whole-word keyword hints (sub first, then a non-generic main).
    for text in (sub_in, "" if generic_main else main_in):
        target = _hint(text, all_subs)
        if target:
            return result(sub_owner[target], target)

    # 3. Fuzzy main (never for generic names); its subs are preferred for a fuzzy sub match.
    fuzzy_main = None
    if exact_main is None and main_in and not generic_main:
        fuzzy_main = _close(main_in, mains, _MAIN_CUTOFF) or _word_overlap(main_in, mains)

    if sub_in:
        if fuzzy_main and subs_of(fuzzy_main):
            fm_subs = subs_of(fuzzy_main)
            hit = _close(sub_in, fm_subs, _SUB_CUTOFF) or _word_overlap(sub_in, fm_subs)
            if hit:
                return result(fuzzy_main, hit)
        hit = _close(sub_in, all_subs, _SUB_CUTOFF) or _word_overlap(sub_in, all_subs)
        if hit:
            return result(sub_owner[hit], hit)

    if fuzzy_main is not None:
        subs = subs_of(fuzzy_main)
        if not subs:
            return result(fuzzy_main, sub_in or fuzzy_main)
        return result(fuzzy_main, _generic_sub(subs))

    # An exact but catch-all main ("Other Income") is used only now, after the sub failed.
    if exact_main is not None:
        subs = subs_of(exact_main)
        if not subs:
            return result(exact_main, sub_in or exact_main)
        return result(exact_main, _sub_in_main(sub_in, subs) or _ci_lookup(fb_sub_name, subs) or _generic_sub(subs))

    # 4. Nothing matched: the type's catch-all category.
    fb_subs = subs_of(fb_main)
    if not fb_subs:
        return result(fb_main, fb_sub_name)
    return result(fb_main, _ci_lookup(fb_sub_name, fb_subs) or _generic_sub(fb_subs))


def parse_positive_amount(value) -> Tuple[Optional[float], bool]:
    """(amount, sign_flipped): abs() of a finite non-zero number, or (None, False) if unusable."""
    try:
        amount = float(value)
    except (TypeError, ValueError):
        return None, False
    if not math.isfinite(amount) or amount == 0:
        return None, False
    return abs(amount), amount < 0
