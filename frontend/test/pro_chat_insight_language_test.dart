import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/models/insight.dart';
import 'package:frontend/models/notification.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/insight_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

/// A streamer that records the mode each message was sent with and, like the
/// server, opens with the meta frame.
class _FakeChat {
  final List<ChatMode> sentModes = [];
  ChatStreamMeta? meta;

  Stream<String> call({
    required String message,
    List<ChatMessage>? chatHistory,
    ResponseStyle? responseStyle,
    ChatMode mode = ChatMode.standard,
    void Function(ChatStreamMeta meta)? onMeta,
  }) async* {
    sentModes.add(mode);
    final m = meta;
    if (m != null) onMeta?.call(m);
    yield 'An answer';
  }
}

Insight _insight({String? mm, bool locked = false, TranslationUnavailable? unavailable}) => Insight(
      id: 'i1',
      userId: 'u1',
      content: 'English text',
      contentMm: mm,
      generatedAt: DateTime.utc(2026, 11, 2),
      translationLocked: locked,
      translationUnavailable: unavailable,
    );

const _capNote = TranslationUnavailable(
  code: 'plan_cost_cap',
  message: 'You have reached this month\'s AI limit.',
  upgradeAvailable: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('chat mode on the wire', () {
    test('the request carries the mode, Standard by default', () {
      expect(ChatRequest(message: 'hi').toJson()['mode'], 'standard');
      expect(ChatRequest(message: 'hi', mode: ChatMode.advanced).toJson()['mode'], 'advanced');
    });

    test('the first stream frame is read into a meta', () {
      final meta = ChatStreamMeta.fromFrame(
          {'chunk': '', 'done': false, 'mode_used': 'standard', 'advanced_exhausted': true});
      expect(meta.modeUsed, ChatMode.standard);
      expect(meta.advancedExhausted, isTrue);

      final advanced = ChatStreamMeta.fromFrame({'mode_used': 'advanced', 'advanced_exhausted': false});
      expect(advanced.modeUsed, ChatMode.advanced);
      expect(advanced.advancedExhausted, isFalse);

      // An unknown value never means Advanced.
      expect(ChatStreamMeta.fromFrame({'mode_used': 'ultra'}).modeUsed, ChatMode.standard);
    });
  });

  group('ChatProvider Standard / Advanced', () {
    test('a plan without Advanced always sends Standard', () async {
      final fake = _FakeChat();
      final p = ChatProvider(streamer: fake.call);
      await p.setMode(ChatMode.advanced); // e.g. remembered from when the user was Pro

      expect(p.advancedAvailable, isFalse);
      expect(p.mode, ChatMode.standard);
      await p.sendMessage('hi');
      await _settle();
      expect(fake.sentModes, [ChatMode.standard]);
    });

    test('Pro sends the chosen mode, and the choice is remembered on the device', () async {
      final fake = _FakeChat();
      final p = ChatProvider(streamer: fake.call)..setAdvancedAvailable(true);

      await p.sendMessage('one');
      await _settle();
      await p.setMode(ChatMode.advanced);
      await p.sendMessage('two');
      await _settle();
      expect(fake.sentModes, [ChatMode.standard, ChatMode.advanced]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ChatProvider.modePrefsKey), 'advanced');

      // A fresh provider (app restart) reads it back.
      final again = ChatProvider(streamer: fake.call)..setAdvancedAvailable(true);
      await again.loadMode();
      expect(again.mode, ChatMode.advanced);
    });

    test('Advanced used up: the switch returns to Standard and a note is raised', () async {
      final fake = _FakeChat()
        ..meta = const ChatStreamMeta(modeUsed: ChatMode.standard, advancedExhausted: true);
      final p = ChatProvider(streamer: fake.call)..setAdvancedAvailable(true);
      await p.setMode(ChatMode.advanced);

      await p.sendMessage('hi');
      await _settle();

      expect(fake.sentModes, [ChatMode.advanced]);
      expect(p.mode, ChatMode.standard);
      expect(p.advancedUsedUp, isTrue);
      // The answer itself is kept: it was answered, by Standard.
      expect(p.messages.map((m) => m.content), ['hi', 'An answer']);
      expect((await SharedPreferences.getInstance()).getString(ChatProvider.modePrefsKey), 'standard');

      // The next message clears the note.
      fake.meta = null;
      await p.sendMessage('again');
      await _settle();
      expect(p.advancedUsedUp, isFalse);
      expect(fake.sentModes.last, ChatMode.standard);
    });

    test('a Standard message flagged exhausted does not raise the note', () async {
      final fake = _FakeChat()
        ..meta = const ChatStreamMeta(modeUsed: ChatMode.standard, advancedExhausted: true);
      final p = ChatProvider(streamer: fake.call)..setAdvancedAvailable(true);

      await p.sendMessage('hi');
      await _settle();

      expect(p.advancedUsedUp, isFalse);
    });

    test('an Advanced answer keeps the switch on Advanced', () async {
      final fake = _FakeChat()..meta = const ChatStreamMeta(modeUsed: ChatMode.advanced);
      final p = ChatProvider(streamer: fake.call)..setAdvancedAvailable(true);
      await p.setMode(ChatMode.advanced);

      await p.sendMessage('hi');
      await _settle();

      expect(p.mode, ChatMode.advanced);
      expect(p.advancedUsedUp, isFalse);
    });

    test('losing Pro hides Advanced; reset forgets the in-memory state', () async {
      final fake = _FakeChat();
      final p = ChatProvider(streamer: fake.call)..setAdvancedAvailable(true);
      await p.setMode(ChatMode.advanced);

      p.setAdvancedAvailable(false);
      expect(p.mode, ChatMode.standard);

      p.setAdvancedAvailable(true);
      expect(p.mode, ChatMode.advanced);
      p.reset();
      expect(p.advancedAvailable, isFalse);
      expect(p.mode, ChatMode.standard);
      expect(p.advancedUsedUp, isFalse);
    });
  });

  group('insight language', () {
    test('wantedLanguage: starts on the app language, always English without translation', () async {
      final p = InsightProvider(fetcher: ({required language, required insightType}) async => _insight());

      expect(p.wantedLanguage(translationAvailable: true, appLanguage: 'mm'), 'mm');
      expect(p.wantedLanguage(translationAvailable: true, appLanguage: 'en'), 'en');
      expect(p.wantedLanguage(translationAvailable: false, appLanguage: 'mm'), 'en');

      // A remembered choice beats the app language, but not a missing translation.
      SharedPreferences.setMockInitialValues({InsightProvider.languagePrefsKey: 'en'});
      await p.loadPreferredLanguage();
      expect(p.wantedLanguage(translationAvailable: true, appLanguage: 'mm'), 'en');
      SharedPreferences.setMockInitialValues({InsightProvider.languagePrefsKey: 'mm'});
      await p.loadPreferredLanguage();
      expect(p.wantedLanguage(translationAvailable: true, appLanguage: 'en'), 'mm');
      expect(p.wantedLanguage(translationAvailable: false, appLanguage: 'en'), 'en');
    });

    test('requests carry the toggle language, and Myanmar is fetched once then flipped for free', () async {
      final asked = <String>[];
      final p = InsightProvider(fetcher: ({required language, required insightType}) async {
        asked.add(language);
        return _insight(mm: language == 'mm' ? 'မြန်မာ စာသား' : null);
      });

      await p.fetchInsights(language: 'en', insightType: 'monthly');
      expect(p.currentLanguage, 'en');

      expect(await p.showLanguage('mm'), isTrue);
      expect(p.currentLanguage, 'mm');
      expect(p.getContentForLanguage(), 'မြန်မာ စာသား');
      expect(asked, ['en', 'mm']);

      // The translation is stored: switching back and forth makes no request.
      expect(await p.showLanguage('en'), isTrue);
      expect(p.getContentForLanguage(), 'English text');
      expect(await p.showLanguage('mm'), isTrue);
      expect(asked, ['en', 'mm']);

      await _settle();
      expect((await SharedPreferences.getInstance()).getString(InsightProvider.languagePrefsKey), 'mm');
    });

    test('a plan without translation answers in English: translation_locked keeps English on screen', () async {
      final p = InsightProvider(
          fetcher: ({required language, required insightType}) async => _insight(locked: language == 'mm'));

      await p.fetchInsights(language: 'en', insightType: 'monthly');
      expect(await p.showLanguage('mm'), isFalse);

      expect(p.currentLanguage, 'en');
      expect(p.insight!.translationLocked, isTrue);
      expect(p.getContentForLanguage(), 'English text');
      await _settle();
      expect((await SharedPreferences.getInstance()).getString(InsightProvider.languagePrefsKey), isNull);

      // fetchInsights with Myanmar asked for on such a plan also shows English.
      await p.fetchInsights(language: 'mm', insightType: 'monthly');
      expect(p.currentLanguage, 'en');
    });

    test('a failed translation keeps the insight and reports the failure', () async {
      var fail = false;
      final p = InsightProvider(fetcher: ({required language, required insightType}) async {
        if (fail) throw ApiException('The AI is busy.', statusCode: 503);
        return _insight();
      });
      await p.fetchInsights(language: 'en', insightType: 'monthly');
      fail = true;

      expect(await p.showLanguage('mm'), isFalse);

      expect(p.insight, isNotNull);
      expect(p.currentLanguage, 'en');
      expect(p.actionError, 'The AI is busy.');
      expect(p.isLoading, isFalse);
    });

    test('a plan limit while translating is exposed for the limit sheet', () async {
      final p = InsightProvider(fetcher: ({required language, required insightType}) async {
        if (language == 'mm') {
          throw PlanLimitException(
            code: PlanLimitException.codeLimitReached,
            statusCode: 429,
            message: 'Used up',
            feature: 'insight_translation',
            upgradeAvailable: true,
          );
        }
        return _insight();
      });
      await p.fetchInsights(language: 'en', insightType: 'monthly');

      expect(await p.showLanguage('mm'), isFalse);

      expect(p.actionPlanLimit?.feature, 'insight_translation');
      expect(p.insight, isNotNull);
    });

    test('translation_locked is read from the response', () {
      final i = Insight.fromJson({
        'id': 'i',
        'user_id': 'u',
        'content': 'English',
        'content_mm': null,
        'generated_at': '2026-11-02T00:00:00Z',
        'expires_at': null,
        'translation_locked': true,
      });
      expect(i.translationLocked, isTrue);
      expect(i.contentMm, isNull);

      final plain = Insight.fromJson({
        'id': 'i',
        'user_id': 'u',
        'content': 'English',
        'generated_at': '2026-11-02T00:00:00Z',
      });
      expect(plain.translationLocked, isFalse);
      expect(plain.translationUnavailable, isNull);
    });

    test('translation_unavailable is read from the response (an object, or null)', () {
      final refused = Insight.fromJson({
        'id': 'i',
        'user_id': 'u',
        'content': 'English',
        'content_mm': null,
        'generated_at': '2026-11-02T00:00:00Z',
        'expires_at': null,
        'translation_locked': false,
        'translation_unavailable': {
          'code': 'plan_cost_cap',
          'feature': 'insight_translation',
          'resets_at': '2026-12-01T00:00:00Z',
          'upgrade_available': true,
          'message': 'The monthly AI limit is reached.',
        },
      });
      expect(refused.translationLocked, isFalse);
      expect(refused.translationUnavailable?.code, 'plan_cost_cap');
      expect(refused.translationUnavailable?.message, 'The monthly AI limit is reached.');
      expect(refused.translationUnavailable?.upgradeAvailable, isTrue);
      expect(refused.translationUnavailable?.resetsAt?.toUtc(), DateTime.utc(2026, 12, 1));

      final none = Insight.fromJson({
        'id': 'i',
        'user_id': 'u',
        'content': 'English',
        'generated_at': '2026-11-02T00:00:00Z',
        'translation_unavailable': null,
      });
      expect(none.translationUnavailable, isNull);
    });

    test('a refused translation shows the English insight with a note, and keeps the remembered language', () async {
      SharedPreferences.setMockInitialValues({InsightProvider.languagePrefsKey: 'mm'});
      final asked = <String>[];
      final p = InsightProvider(fetcher: ({required language, required insightType}) async {
        asked.add(language);
        return _insight(unavailable: language == 'mm' ? _capNote : null);
      });
      await p.loadPreferredLanguage();

      // Myanmar is the remembered choice, so it is asked for; the server refuses the translation but sends English.
      await p.fetchInsights(language: p.wantedLanguage(translationAvailable: true, appLanguage: 'en'));

      expect(asked, ['mm']);
      expect(p.error, isNull);
      expect(p.errorPlanLimit, isNull);
      expect(p.insight, isNotNull);
      expect(p.getContentForLanguage(), 'English text');
      expect(p.currentLanguage, 'en');
      expect(p.translationNote?.code, 'plan_cost_cap');
      expect(p.translationNote?.message, contains('AI limit'));
      expect(p.insight!.translationLocked, isFalse);

      // The remembered choice is untouched: the next load asks for Myanmar again.
      await _settle();
      expect((await SharedPreferences.getInstance()).getString(InsightProvider.languagePrefsKey), 'mm');
      expect(p.wantedLanguage(translationAvailable: true, appLanguage: 'en'), 'mm');

      // Tapping မြန်မာ asks again (a retry), still no error and no limit sheet.
      expect(await p.showLanguage('mm'), isFalse);
      expect(asked, ['mm', 'mm']);
      expect(p.actionError, isNull);
      expect(p.actionPlanLimit, isNull);
      expect(p.translationNote, isNotNull);

      // Choosing English on purpose drops the note and does not change the answer.
      expect(await p.showLanguage('en'), isTrue);
      expect(p.translationNote, isNull);
      expect(p.currentLanguage, 'en');
    });

    test('the note can be closed: hidden for this insight, the remembered language untouched', () async {
      SharedPreferences.setMockInitialValues({InsightProvider.languagePrefsKey: 'mm'});
      final asked = <String>[];
      final p = InsightProvider(fetcher: ({required language, required insightType}) async {
        asked.add(language);
        return _insight(unavailable: language == 'mm' ? _capNote : null);
      });
      await p.loadPreferredLanguage();
      await p.fetchInsights(language: 'mm');
      expect(p.translationNote, isNotNull);
      var notified = 0;
      p.addListener(() => notified++);

      p.dismissTranslationNote();

      expect(p.translationNote, isNull);
      expect(notified, 1);
      expect(p.insight, isNotNull); // the insight itself stays
      expect(p.currentLanguage, 'en');
      await _settle();
      expect((await SharedPreferences.getInstance()).getString(InsightProvider.languagePrefsKey), 'mm');
      expect(p.wantedLanguage(translationAvailable: true, appLanguage: 'en'), 'mm');

      p.dismissTranslationNote(); // nothing to close any more: no extra rebuild
      expect(notified, 1);

      // A later load that is refused again brings the note back for that insight.
      await p.fetchInsights(language: 'mm');
      expect(p.translationNote, isNotNull);
    });

    test('next_insight_at is read from the response (an instant, or missing)', () {
      final withDate = Insight.fromJson({
        'id': 'i',
        'user_id': 'u',
        'content': 'English',
        'generated_at': '2026-11-02T00:00:00Z',
        'next_insight_at': '2026-11-09T22:30:00Z',
      });
      expect(withDate.nextInsightAt?.toUtc(), DateTime.utc(2026, 11, 9, 22, 30));

      final none = Insight.fromJson({
        'id': 'i',
        'user_id': 'u',
        'content': 'English',
        'generated_at': '2026-11-02T00:00:00Z',
        'next_insight_at': null,
      });
      expect(none.nextInsightAt, isNull);
      expect(Insight.fromJson({
        'id': 'i',
        'user_id': 'u',
        'content': 'English',
        'generated_at': '2026-11-02T00:00:00Z',
      }).nextInsightAt, isNull);
    });

    test('a refused translation does not stick once Myanmar is available again', () async {
      var refuse = true;
      final p = InsightProvider(
          fetcher: ({required language, required insightType}) async => language == 'mm'
              ? (refuse ? _insight(unavailable: _capNote) : _insight(mm: 'မြန်မာ'))
              : _insight());
      await p.fetchInsights(language: 'mm');
      expect(p.translationNote, isNotNull);

      refuse = false;
      expect(await p.showLanguage('mm'), isTrue);
      expect(p.translationNote, isNull);
      expect(p.currentLanguage, 'mm');
      expect(p.getContentForLanguage(), 'မြန်မာ');
    });
  });

  group('trial reminder notifications', () {
    Map<String, dynamic> json(String type) => {
          'id': 'n1',
          'user_id': 'u1',
          'type': type,
          'title': 'Your Plus Trial Ends Soon',
          'message': 'Upgrade before then.',
          'created_at': '2026-11-02T00:00:00Z',
          'is_read': false,
        };

    test('both trial types are known types, not a system broadcast', () {
      expect(AppNotification.fromJson(json('trial_ending_soon')).type, NotificationType.trial_ending_soon);
      expect(AppNotification.fromJson(json('trial_ends_today')).type, NotificationType.trial_ends_today);
      expect(AppNotification.fromJson(json('something_new')).type, NotificationType.system_broadcast);
    });
  });

  group('plan_activated / upgrade_request_declined notifications', () {
    Map<String, dynamic> json(String type) => {
          'id': 'n1',
          'user_id': 'u1',
          'type': type,
          'title': 'Your Plus Plan Is Active',
          'message': 'Your Plus plan is now active.',
          'created_at': '2026-11-03T00:00:00Z',
          'is_read': false,
        };

    test('both types are known types, not a system broadcast', () {
      expect(AppNotification.fromJson(json('plan_activated')).type, NotificationType.plan_activated);
      expect(AppNotification.fromJson(json('upgrade_request_declined')).type,
          NotificationType.upgrade_request_declined);
    });

    test('they are plan notices (plan icon and colour, open the Upgrade screen), like the trial and expiry ones', () {
      for (final type in [
        NotificationType.plan_activated,
        NotificationType.upgrade_request_declined,
        NotificationType.subscription_expired,
        NotificationType.trial_ending_soon,
        NotificationType.trial_ends_today,
      ]) {
        expect(type.isPlanNotice, isTrue, reason: type.name);
      }
      for (final type in [NotificationType.goal_achieved, NotificationType.system_broadcast, NotificationType.budget_exceeded]) {
        expect(type.isPlanNotice, isFalse, reason: type.name);
      }
    });

    test('only the two new types make the app reload the plan', () {
      expect(notificationRefreshesPlan('plan_activated'), isTrue);
      expect(notificationRefreshesPlan('upgrade_request_declined'), isTrue);
      for (final other in ['trial_ending_soon', 'subscription_expired', 'goal_progress', 'subscription_updated', '', null]) {
        expect(notificationRefreshesPlan(other), isFalse, reason: '$other');
      }
    });
  });
}
