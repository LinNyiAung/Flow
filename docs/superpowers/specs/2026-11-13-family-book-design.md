# Family book: design

## Intent
Toe Pwar is a personal money app. Households, mostly parents, also want to keep the **family's** money together: one shared book of household income and spending, its own budgets and savings goals, and at the end of the month an answer to two questions: "how much did we spend?" and "who did we spend it on?" (Mum, Dad, Ma Ma, Grandma, the whole family).

Some of the people the money is for, like young children or grandparents, don't have the app. So a family can also hold **placeholder** members: names you can tag entries with.

## Goals
- **Shared book:** account holders form a family with one shared family book, which has its own wallet, budgets and goals.
- **Who it was for:** every family entry records who it was for: the whole family, one person, or several people. The monthly view breaks spending down by person.
- **Personal stays private:** nobody else ever sees your personal book.
- **One switch:** a single Personal / Family switch moves the whole app between the two books. Every existing screen works on whichever book you're in.

## Non-goals (first version)
- Splitting one entry by **different** amounts per person. That takes separate entries.
- Belonging to more than one family.
- A family-only theme, icon or look.
- A notification for every family entry.

## Anti-goals (a failure even if everything else works)
- **A leak:** any of a person's Personal entries, totals or balances becomes visible to another family member, in any screen, report, export, insight or Ko Toe Pwar answer.
- **Lost history:** a member leaving or being removed deletes or rewrites family history.
- **Money mixing:** personal and family money mix in a balance, or money appears or disappears in a transfer. Every transfer is one linked pair.
- **Confusing book:** people can't tell which book they're looking at, or which book a new entry will land in.

## Owner's decisions

### People and roles
- **One family per person.** To join another family you must leave yours first.
- **Account members** have their own Toe Pwar account and join by invitation. There are at most **6** per family, the owner included.
- **Placeholder members** are names only, such as "Ma Ma" or "Grandma". There are at most **20** per family. They don't log in and have no powers; they exist so entries can be tagged with them.
- **A placeholder can become a real member:** when that person gets an account and is invited, the placeholder turns into their account and keeps every entry already tagged to it. No duplicate name is left behind.
- **Roles:**
  - **Owner:** the creator; there is exactly one. Only the owner can:
    - make or unmake admins;
    - hand ownership to another account member;
    - delete the family.
  - **Admins:** promoted by the owner. They can:
    - invite and remove members, and add, rename or remove placeholders;
    - create and change family budgets and goals (admins only);
    - edit or delete **anyone's** family entries.
  - **Members:** all other account members. They can:
    - add family entries;
    - move money between their wallet and the family wallet;
    - see the whole family book, budgets and goals;
    - edit or delete **only the entries they added themselves**.

### Invitations
- **How:** an admin invites by **email**, using the address the person signed up with. The invitee sees it in the app and as a notification, and taps **Join** or **Decline**.
- **Linking to a placeholder:** an invite can be linked to a placeholder. On joining, the placeholder becomes that person (see above).
- **Expiry:** an invite expires after **14 days**. An admin can cancel it before then.
- **Already in a family:** a person who already belongs to a family can't accept until they leave it.

### The two books and the switch
- **The switch:** members of a family get a **Personal / Family** switch at the top of the dashboard and in the side menu. It changes the whole app:
  - the dashboard, transactions, budgets, goals, analytics and reports;
  - Ko Toe Pwar's chat.

  In Family mode you see only the family book; in Personal mode only yours.
- **Adding an entry:** the **+ button** adds to the book you're in. The add screen shows which book the entry goes to, and lets you switch it to the other book before saving.
- **No family:** people who aren't in a family see no switch, and the app is exactly as it is today.
- **Privacy:** Personal entries are completely private. Other members never see them, not even as a total. Every account member sees all Family entries.

### Family entries
- **Who it was for:** "**Whole family**" (the default), **one member**, or **several members**. Any member counts, placeholders included.
  - **Split evenly:** an entry for several members is split evenly in the per-person view. K60,000 for Ma Ma and Ko Ko counts as K30,000 each.
- **Who added it:** recorded automatically and shown on the entry. The per-person breakdown is by **who it was for**, not by who added it.
- **Whole family has its own row:** "Whole family" spending appears as its own row in the per-person breakdown and is not divided among members.

### The family wallet and transfers
- **Separate wallet:** the family has its own wallet and balance, separate from everyone's personal wallets. Personal and family balances never mix. Like personal books, it has a separate balance per currency (USD, MMK, THB).
- **Money in:** family income is recorded straight into the family wallet, for example Dad records his salary there.
- **Personal → family:** in Personal mode, "**Move to family wallet**" moves money out of your wallet and into the family's. It is recorded as **one linked transfer**: money out on your side and money in on the family side.
- **Family → personal:** any member can move money out of the family wallet into their own, like taking cash from the household jar. It is recorded the same linked way, so everyone can see who took what.
- **Family spending** comes out of the family wallet.

### Family budgets and goals
- **Budgets:** families have their own budgets, which work like personal budgets on family spending. Only admins create and change them; everyone sees them.
- **Goals:** families have their own savings goals, which work like personal goals with money set aside from the family wallet. Everyone sees them.
  - **Any member** can **add money** to a family goal from the family wallet.
  - Only **admins** can **take money out** of a goal, or create, edit or delete one.

### Leaving and removal
- **History stays:** when someone leaves or is removed, their family entries stay in the family book.
- **Their name stays:** it remains on their entries and on anything tagged for them, marked as a **former member**, so the history still adds up. An admin can rename or tidy it later.
- **Their money stays:** anything they moved into the family wallet stays there.

### Deleting the family
- **Who:** only the owner, after a typed confirmation.
- **What goes:** the family's entries, budgets, goals and members are deleted for everyone.
- **What stays:** personal books are never touched. Transfers people made into or out of the family stay in their personal history.

### Plans
- **Creating a family** needs **Plus or Pro**. Free users see "Create a family" with an Upgrade path.
- **Joining is free:** anyone can join, on any plan.
- **Size:** Plus and Pro both allow 6 account members and 20 placeholders.
- **If the owner's plan lapses:**
  - nothing is deleted; the family turns **read-only** for everyone (they can see entries, budgets and goals but can't add or change anything);
  - this lasts until the owner renews, or hands ownership to a member who is on Plus or Pro.

### Ko Toe Pwar
- **Family mode:** Ko Toe Pwar answers about the **family book**, e.g. "how much did we spend on Ma Ma this month?". He never uses anyone's personal data there.
- **Chat history is private to each person,** in Family mode too. Only the data he answers from is shared. Nobody sees or clears another member's questions.
- **Personal mode:** he answers about your own book, as today.
- **Allowance:** each person's questions count against **their own** plan's allowance.
- **Family insights:** the family book gets weekly and monthly insights too, shown in the Insights screen in Family mode.

### Notifications
- **All account members are notified:**
  - when a family budget is close to its cap or over it;
  - when a family goal is reached.
- **Invitations:** the invitee is notified when invited.
- **No per-entry notifications.**

## How it fits the existing system
- **Today's design:** everything is keyed to one user. `transactions`, `budgets` (+ `budget_allocations`), `goals`, `insights`, `chat_sessions` and `notifications` each carry a `user_id`.
  - **The core of the change:** each of these must belong to **either** a user's personal book **or** a family book.
  - **The risky part:** every existing query that reads a personal book must keep returning only that person's personal records.
- **Plans:** creating a family checks the existing plan system, with the current Plus/Pro gating. The member limits should be stored the same way other plan limits are (`plan_limits`), so the admin Plans page can show and edit them.
- **AI:** chat and insights already build a context from one user's data. Family mode builds it from the family book instead. Ko Toe Pwar's persona, the quotas and the cost cap are unchanged.
- **Mascot:** Ko Toe Pwar's existing placement rules apply to family screens too:
  - empty states only when the family truly has no data;
  - not on sign-in, register or plans.
- **Both languages:** every new screen and message is in English and Myanmar.

## Claude's calls (the builder may refine these)
- **Transfers aren't income or spending.** A move between a personal wallet and the family wallet only changes the two balances. Transfers are left out of:
  - income and spending totals;
  - budget spending, analytics, reports and insights;
  - the per-person breakdown;
  - Ko Toe Pwar's income and spending figures.

  They still appear in both books' entry lists, marked as transfers, with who made them, so "who took what" stays visible. This needs a transfer marker on transactions that every total excludes.
- **Undoing a transfer:**
  - transfers can't be edited;
  - only the person who made one can undo it, and undoing removes **both sides** together;
  - admins can't undo someone else's transfer, because that would change that person's personal book.
- **Former members and placeholders:**
  - someone who left and is invited again is reconnected to their former-member record, so old and new entries count as one person; an invite can link to a former member as well as to a placeholder;
  - removing a placeholder that has tagged entries marks it as former (hidden from the "for whom" picker, still shown on old entries and in past breakdowns); one with no entries is simply deleted;
  - tags are never dropped.
- **The owner leaving:** the owner can't leave without handing over ownership first. If they leave anyway (e.g. by deleting their account), the deleted-account rule below applies.
- **Chat storage:** chat sessions and messages stay per user. A session records which book it is about (personal, or the family), and Family mode shows and clears only the caller's own family-mode history.
- **Storage:**
  - new tables for families, family members (account or placeholder, role, active or former, display name) and invitations;
  - `transactions`, `budgets` and `goals` gain a nullable family reference;
  - an entry with a family reference belongs to the family book, and its `user_id` is who added it;
  - "who it was for" is a small link table: no rows means Whole family.

  A transfer is two linked transactions that share a transfer id: an outflow in one book and an inflow in the other.
- **Privacy is enforced on the server.** Every endpoint resolves the book from the request (personal, or the caller's family after checking membership and role), never from a client-supplied user id. Tests must prove a member can't read another member's personal data through any endpoint, the chat context or the insights.
- **Recurring entries, voice entry and receipt scanning:**
  - all work in Family mode, creating family entries;
  - AI entry counts against the person using it;
  - recurring family entries keep running after their creator leaves, until an admin stops them.
- **Reports:** reports, charts and PDF export work in Family mode. PDF export depends on the exporting person's own plan.
- **Deleted accounts:**
  - a member who deletes their account becomes a former member, like leaving;
  - if the owner deletes their account, ownership passes to the longest-standing admin, otherwise to the longest-standing account member;
  - if nobody is left, the family is deleted.
- **Family insights** run on the owner's plan schedule (weekly for Plus and Pro) and don't use any member's allowance.
- **The mode** is remembered per device and defaults to Personal.
- **Category names, currencies and the money and date formats** are the app's existing ones.
- **The admin panel** gets no family management in the first version.

## Open for the owner
None at the moment. Every point above was discussed and agreed, or is marked as Claude's call.
