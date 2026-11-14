import 'package:flutter/widgets.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/models/transaction.dart';
import 'package:frontend/providers/book_mode_provider.dart';
import 'package:frontend/providers/family_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';
import 'package:provider/provider.dart';

/// Whether the app shows the family book (the entries on screen belong to
/// it). False where the family providers aren't in the tree.
bool showsFamilyBook(BuildContext context, {bool listen = true}) =>
    Provider.of<BookModeProvider?>(context, listen: listen)?.isFamily ?? false;

/// A transfer leg's label, from the book it is in and its type: money into
/// the family wallet is the personal outflow and the family inflow.
String transferLabel(AppLocalizations l, Transaction t, {required bool familyBook}) {
  final intoFamily = familyBook ? t.type == TransactionType.inflow : t.type == TransactionType.outflow;
  return intoFamily ? l.transferToFamily : l.transferFromFamily;
}

/// Whether the signed-in person may change (edit or delete) [t]: always in a
/// personal book; in the family book an admin, or whoever added it. An entry
/// with no recorded adder (from before) is for admins only, as the server says.
bool canChangeEntry(Transaction t, {required bool familyBook, FamilyProvider? family}) {
  if (!familyBook) return true;
  if (family == null) return false;
  if (family.isAdmin) return true;
  final me = family.me?.id;
  return me != null && t.addedBy?.memberId == me;
}

/// Whether the signed-in person made transfer leg [t] (only they can undo
/// it): a personal leg is always theirs; a family leg when they added it.
bool madeTransfer(Transaction t, {required bool familyBook, FamilyProvider? family}) {
  if (!familyBook) return true;
  final me = family?.me?.id;
  return me != null && t.addedBy?.memberId == me;
}

/// [ref]'s name, with "(former)" when the family lists them as a former member.
String memberRefName(AppLocalizations l, FamilyMemberRef ref, FamilyProvider? family) {
  for (final m in family?.members ?? const <FamilyMember>[]) {
    if (m.id == ref.memberId) {
      return m.isFormer ? l.familyFormerName(ref.displayName) : ref.displayName;
    }
  }
  return ref.displayName;
}

/// "Whole family" for no tags, else the names of the tagged members in the
/// family's order (former ones marked; unknown ids skipped).
String forWhomSummary(AppLocalizations l, List<String> forWhom, FamilyProvider? family) {
  if (forWhom.isEmpty) return l.wholeFamily;
  final names = <String>[];
  for (final m in family?.members ?? const <FamilyMember>[]) {
    if (forWhom.contains(m.id)) names.add(m.isFormer ? l.familyFormerName(m.displayName) : m.displayName);
  }
  return names.isEmpty ? l.wholeFamily : names.join(', ');
}

/// The message for a refused transfer or undo: `transfer_insufficient` and
/// `transfer_gone` in the app's own words ([undo]: the destination already
/// used the money), otherwise the server's (already localized) message.
String transferErrorMessage(AppLocalizations l, Object error, {bool undo = false}) {
  if (error is ApiException) {
    switch (error.code) {
      case 'transfer_insufficient':
        return undo ? l.transferUndoInsufficient : l.transferInsufficient;
      case 'transfer_gone':
        return l.transferGone;
      case 'family_read_only':
        return l.familyReadOnlyBanner;
    }
    if (error.message.trim().isNotEmpty && (error.code != null || error.statusCode == null)) {
      return error.message.trim();
    }
  }
  return l.genericErrorOccurred;
}
