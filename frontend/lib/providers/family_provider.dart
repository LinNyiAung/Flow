import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:frontend/models/family.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/localization_service.dart';

/// The signed-in person's family (`GET /api/family`): the family, the
/// members, their own role, the pending invitations (admins) and the
/// invitations they received.
///
/// Loaded when a user signs in (the app root calls [refresh]) and after a
/// family request answers `no_family`. Each change returns null on success or
/// a message to show (the server's own, already in the user's language; a
/// generic one otherwise), and applies the overview the server answered.
class FamilyProvider with ChangeNotifier {
  FamilyOverview _overview = FamilyOverview.none;
  List<FamilyInvite> _myInvites = const [];
  bool _loaded = false;
  bool _isLoading = false;
  String? _error;
  bool _lastErrorReported = false;

  /// Bumped by [reset]: anything that answers for an older generation
  /// (the previous user) is dropped.
  int _generation = 0;

  /// Bumped by each [refresh]; only the newest one may apply or clear
  /// [isLoading].
  int _refreshSeq = 0;

  /// Bumped each time an answer is applied, so a refresh that started before
  /// a change can't overwrite the change's newer answer.
  int _appliedSeq = 0;

  /// True once the family is known (a refresh or a change succeeded) since
  /// the last [reset]. Before that, [inFamily] is false only because nothing
  /// is known yet.
  bool get loaded => _loaded;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// The last change failed with an error the app already reported itself
  /// (a Family-mode `no_family`: the app goes back to Personal and says why),
  /// so the screen must not show the message a change returned.
  bool get lastErrorReported => _lastErrorReported;

  Family? get family => _overview.family;
  bool get inFamily => _overview.family != null;

  /// The owner's plan lapsed: everyone can read, nobody can add or change.
  bool get readOnly => _overview.family?.readOnly ?? false;

  /// Every member, active and former, in join order.
  List<FamilyMember> get members => _overview.members;

  /// The members an entry can be for (former ones are hidden from pickers).
  List<FamilyMember> get activeMembers => members.where((m) => m.isActive).toList();

  /// The signed-in person's member row.
  FamilyMember? get me {
    for (final m in members) {
      if (m.isMe || m.id == _overview.myMemberId) return m;
    }
    return null;
  }

  String? get myRole => _overview.myRole;
  bool get isOwner => _overview.myRole == FamilyMember.roleOwner;

  /// The owner or an admin.
  bool get isAdmin => isOwner || _overview.myRole == FamilyMember.roleAdmin;

  /// The family's pending invitations (admins only; empty for members).
  List<FamilyInvite> get invites => _overview.invites;

  /// Invitations the signed-in person received (see [loadMyInvites]).
  List<FamilyInvite> get myInvites => _myInvites;

  int? get maxMembers => _overview.maxMembers;
  int? get maxPlaceholders => _overview.maxPlaceholders;

  /// Clears all per-user state (logout / another account).
  void reset() {
    _generation++;
    _overview = FamilyOverview.none;
    _myInvites = const [];
    _loaded = false;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Reloads the family. A failure keeps what is shown. Does nothing when
  /// nobody is signed in.
  Future<void> refresh() async {
    if (await ApiService.getToken() == null) return;
    final generation = _generation;
    final seq = ++_refreshSeq;
    final appliedAtStart = _appliedSeq;
    _isLoading = true;
    notifyListeners();
    try {
      final overview = await ApiService.getFamily();
      if (generation != _generation) return;
      if (seq == _refreshSeq && appliedAtStart == _appliedSeq) {
        _apply(overview);
      }
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      _error = _messageOf(e);
      debugPrint('FamilyProvider: refresh failed: $e');
    }
    if (seq == _refreshSeq) _isLoading = false;
    notifyListeners();
  }

  // ---- the family ----

  Future<String?> createFamily(String name) => _change(() => ApiService.createFamily(name));

  Future<String?> renameFamily(String name) => _change(() => ApiService.renameFamily(name));

  /// The owner, with the family's name typed exactly.
  Future<String?> deleteFamily(String confirmName) => _change(() => ApiService.deleteFamily(confirmName));

  // ---- members ----

  Future<String?> addPlaceholder(String displayName) => _change(() => ApiService.addFamilyPlaceholder(displayName));

  /// Renames a placeholder or former member, or (the owner) sets an account
  /// member's [role] ([FamilyMember.roleAdmin] / [FamilyMember.roleMember]).
  Future<String?> updateMember(String memberId, {String? displayName, String? role}) =>
      _change(() => ApiService.updateFamilyMember(memberId, displayName: displayName, role: role));

  Future<String?> removeMember(String memberId) => _change(() => ApiService.removeFamilyMember(memberId));

  Future<String?> leave() => _change(ApiService.leaveFamily);

  Future<String?> transferOwnership(String memberId) => _change(() => ApiService.transferFamilyOwnership(memberId));

  // ---- invitations ----

  /// Invites [email] (optionally as the placeholder or former member
  /// [linkMemberId]); the new invite replaces a pending one to that address.
  Future<String?> invite(String email, {String? linkMemberId}) {
    return _run((generation) async {
      final invite = await ApiService.createFamilyInvite(email, linkMemberId: linkMemberId);
      if (generation != _generation) return;
      final address = invite.email?.toLowerCase();
      _overview = FamilyOverview(
        family: _overview.family,
        myMemberId: _overview.myMemberId,
        myRole: _overview.myRole,
        members: _overview.members,
        invites: [
          ..._overview.invites.where((i) => i.id != invite.id && i.email?.toLowerCase() != address),
          invite,
        ],
        maxMembers: _overview.maxMembers,
        maxPlaceholders: _overview.maxPlaceholders,
      );
      _appliedSeq++;
      notifyListeners();
    });
  }

  Future<String?> cancelInvite(String inviteId) => _change(() => ApiService.cancelFamilyInvite(inviteId));

  /// Loads the invitations the signed-in person received.
  Future<String?> loadMyInvites() {
    return _run((generation) async {
      final invites = await ApiService.getMyFamilyInvites();
      if (generation != _generation) return;
      _myInvites = List.unmodifiable(invites);
      notifyListeners();
    });
  }

  /// Joins that family.
  Future<String?> acceptInvite(String inviteId) async {
    final error = await _change(() => ApiService.acceptFamilyInvite(inviteId));
    if (error == null) _dropMyInvite(inviteId);
    return error;
  }

  Future<String?> declineInvite(String inviteId) {
    return _run((generation) async {
      await ApiService.declineFamilyInvite(inviteId);
      if (generation == _generation) _dropMyInvite(inviteId);
    });
  }

  // ---- internals ----

  void _dropMyInvite(String inviteId) {
    _myInvites = List.unmodifiable(_myInvites.where((i) => i.id != inviteId));
    notifyListeners();
  }

  /// A change whose answer is the family overview.
  Future<String?> _change(Future<FamilyOverview> Function() call) {
    return _run((generation) async {
      final overview = await call();
      if (generation == _generation) _apply(overview);
    });
  }

  /// Runs [body] for the current generation: null when it succeeds,
  /// otherwise the message to show (see [lastErrorReported]).
  ///
  /// A `no_family` refusal means the family is gone: the family is reloaded.
  /// In Family mode the app root already does that (and says why).
  Future<String?> _run(Future<void> Function(int generation) body) async {
    _lastErrorReported = false;
    try {
      await body(_generation);
      return null;
    } catch (e) {
      debugPrint('FamilyProvider: $e');
      if (e is ApiException) {
        _lastErrorReported = e.reported;
        if (e.code == ApiService.noFamilyCode && !e.reported) unawaited(refresh());
      }
      return _messageOf(e);
    }
  }

  /// Tests: shows [overview] (and [myInvites]) as if the server had answered.
  @visibleForTesting
  void debugApply(FamilyOverview overview, {List<FamilyInvite>? myInvites}) {
    if (myInvites != null) _myInvites = List.unmodifiable(myInvites);
    _apply(overview);
  }

  void _apply(FamilyOverview overview) {
    _overview = overview;
    _loaded = true;
    _appliedSeq++;
    notifyListeners();
  }

  /// The server's coded message (already in the user's language), a
  /// timeout / network message (also localized), or a generic one.
  static String _messageOf(Object e) {
    if (e is ApiException && (e.code != null || e.statusCode == null) && e.message.trim().isNotEmpty) {
      return e.message.trim();
    }
    return AppLocalizations(Locale(ApiService.currentLanguage)).genericErrorOccurred;
  }
}
