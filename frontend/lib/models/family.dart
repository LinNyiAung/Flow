import 'package:frontend/models/user.dart';
import 'package:frontend/utils/date_parsing.dart';

/// Which book the whole app works on: the person's own, or their family's.
/// Sent as the `X-Book` header (see `ApiService.bookMode`).
enum BookMode {
  personal,
  family;

  /// [name] as stored on the device; anything unknown is Personal.
  static BookMode fromName(String? name) => name == family.name ? family : personal;
}

String? _string(dynamic value) => value is String ? value : null;

double _double(dynamic value) => value is num ? value.toDouble() : 0;

/// `family` of `GET /api/family`.
class Family {
  final String id;
  final String name;

  /// The owner's plan isn't Plus or Pro: everyone can read, nobody can add or change.
  final bool readOnly;

  const Family({required this.id, required this.name, this.readOnly = false});

  factory Family.fromJson(Map<String, dynamic> json) => Family(
        id: json['id'] as String,
        name: _string(json['name']) ?? '',
        readOnly: json['read_only'] == true,
      );
}

/// A member of the family: an account member or a placeholder (a name only),
/// active or former (left or removed; kept so history still adds up).
class FamilyMember {
  static const String kindAccount = 'account';
  static const String kindPlaceholder = 'placeholder';
  static const String roleOwner = 'owner';
  static const String roleAdmin = 'admin';
  static const String roleMember = 'member';
  static const String statusActive = 'active';
  static const String statusFormer = 'former';

  final String id;
  final String displayName;

  /// [kindAccount] or [kindPlaceholder].
  final String kind;

  /// [roleOwner], [roleAdmin] or [roleMember]; null for a placeholder.
  final String? role;

  /// [statusActive] or [statusFormer].
  final String status;

  /// This member is the signed-in person.
  final bool isMe;

  const FamilyMember({
    required this.id,
    required this.displayName,
    required this.kind,
    this.role,
    this.status = statusActive,
    this.isMe = false,
  });

  bool get isAccount => kind == kindAccount;
  bool get isPlaceholder => kind == kindPlaceholder;
  bool get isActive => status == statusActive;
  bool get isFormer => status == statusFormer;
  bool get isOwner => role == roleOwner;

  /// The owner or an admin.
  bool get isAdmin => role == roleOwner || role == roleAdmin;

  factory FamilyMember.fromJson(Map<String, dynamic> json) => FamilyMember(
        id: json['id'] as String,
        displayName: _string(json['display_name']) ?? '',
        kind: _string(json['kind']) ?? kindAccount,
        role: _string(json['role']),
        status: _string(json['status']) ?? statusActive,
        isMe: json['is_me'] == true,
      );
}

/// An invitation: one the family sent (`invites` of `GET /api/family`, admins
/// only; it has [email] and [linkMemberId]) or one the signed-in person
/// received (`GET /api/family/invites/mine`; it has [familyName] and [invitedBy]).
class FamilyInvite {
  final String id;
  final String? email;

  /// The placeholder or former member the invitee becomes on joining, or null.
  final String? linkMemberId;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String? familyId;
  final String? familyName;

  /// The inviting admin's name.
  final String? invitedBy;

  const FamilyInvite({
    required this.id,
    this.email,
    this.linkMemberId,
    this.createdAt,
    this.expiresAt,
    this.familyId,
    this.familyName,
    this.invitedBy,
  });

  factory FamilyInvite.fromJson(Map<String, dynamic> json) => FamilyInvite(
        id: json['id'] as String,
        email: _string(json['email']),
        linkMemberId: _string(json['link_member_id']),
        createdAt: parseInstantOrNull(json['created_at']),
        expiresAt: parseInstantOrNull(json['expires_at']),
        familyId: _string(json['family_id']),
        familyName: _string(json['family_name']),
        invitedBy: _string(json['invited_by']),
      );
}

/// Who recorded a family entry (`added_by` of a transaction).
class FamilyMemberRef {
  final String memberId;
  final String displayName;

  const FamilyMemberRef({required this.memberId, required this.displayName});

  /// Null for anything that isn't `{member_id, display_name}` (a personal entry).
  static FamilyMemberRef? tryParse(dynamic json) {
    if (json is! Map) return null;
    final id = json['member_id'];
    if (id is! String) return null;
    return FamilyMemberRef(memberId: id, displayName: _string(json['display_name']) ?? '');
  }
}

/// One row of the per-person spending breakdown.
class BreakdownRow {
  /// Null for the "Whole family" row.
  final String? memberId;

  /// The server's name for the row ("Whole family" in English for the
  /// [isWholeFamily] row: show the app's own string for that one).
  final String displayName;

  /// `active` or `former`.
  final String status;
  final double amount;

  const BreakdownRow({this.memberId, required this.displayName, this.status = 'active', required this.amount});

  bool get isWholeFamily => memberId == null;
  bool get isFormer => status == FamilyMember.statusFormer;

  factory BreakdownRow.fromJson(Map<String, dynamic> json) => BreakdownRow(
        memberId: _string(json['member_id']),
        displayName: _string(json['display_name']) ?? '',
        status: _string(json['status']) ?? FamilyMember.statusActive,
        amount: _double(json['amount']),
      );
}

/// `GET /api/family/breakdown`: spending per person it was for, largest first.
class FamilyBreakdown {
  final Currency currency;
  final double totalSpent;
  final List<BreakdownRow> rows;

  const FamilyBreakdown({required this.currency, required this.totalSpent, required this.rows});

  factory FamilyBreakdown.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'];
    return FamilyBreakdown(
      currency: Currency.fromString(_string(json['currency']) ?? 'usd'),
      totalSpent: _double(json['total_spent']),
      rows: rows is List
          ? rows.whereType<Map>().map((r) => BreakdownRow.fromJson(Map<String, dynamic>.from(r))).toList()
          : const [],
    );
  }
}

/// `GET /api/family` (and the answer of most family changes): the family, the
/// caller's member id and role, every member, the pending invites (admins
/// only) and the owner's limits. [family] is null outside a family.
class FamilyOverview {
  final Family? family;
  final String? myMemberId;
  final String? myRole;
  final List<FamilyMember> members;
  final List<FamilyInvite> invites;
  final int? maxMembers;
  final int? maxPlaceholders;

  const FamilyOverview({
    this.family,
    this.myMemberId,
    this.myRole,
    this.members = const [],
    this.invites = const [],
    this.maxMembers,
    this.maxPlaceholders,
  });

  static const FamilyOverview none = FamilyOverview();

  factory FamilyOverview.fromJson(dynamic json) {
    if (json is! Map || json['family'] is! Map) return none;
    final me = json['me'];
    final limits = json['limits'];
    List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) => raw is List
        ? raw.whereType<Map>().map((e) => parse(Map<String, dynamic>.from(e))).toList()
        : <T>[];
    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    return FamilyOverview(
      family: Family.fromJson(Map<String, dynamic>.from(json['family'] as Map)),
      myMemberId: me is Map ? _string(me['member_id']) : null,
      myRole: me is Map ? _string(me['role']) : null,
      members: list(json['members'], FamilyMember.fromJson),
      invites: list(json['invites'], FamilyInvite.fromJson),
      maxMembers: limits is Map ? asInt(limits['max_members']) : null,
      maxPlaceholders: limits is Map ? asInt(limits['max_placeholders']) : null,
    );
  }
}

/// Which way a transfer moves money.
enum TransferDirection {
  /// Out of the caller's wallet into the family's.
  toFamily('to_family'),

  /// Out of the family's wallet into the caller's.
  toPersonal('to_personal');

  final String wireName;
  const TransferDirection(this.wireName);
}

/// The answer of `POST /api/transfers`: the transfer and its two legs.
class TransferResult {
  final String transferId;
  final String? personalTransactionId;
  final String? familyTransactionId;

  const TransferResult({required this.transferId, this.personalTransactionId, this.familyTransactionId});

  factory TransferResult.fromJson(Map<String, dynamic> json) => TransferResult(
        transferId: json['transfer_id'] as String,
        personalTransactionId: _string(json['personal_transaction_id']),
        familyTransactionId: _string(json['family_transaction_id']),
      );
}
