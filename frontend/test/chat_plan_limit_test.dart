import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/services/api_service.dart';

PlanLimitException _limit() => PlanLimitException(
      code: PlanLimitException.codeLimitReached,
      statusCode: 429,
      message: 'You have used all your AI chat messages.',
      feature: 'chat',
      upgradeAvailable: true,
    );

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('a message the plan refuses leaves the conversation and raises the limit', () async {
    final provider = ChatProvider(
      streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) =>
          Stream<String>.error(_limit()),
    );

    await provider.sendMessage('how much did I spend?');
    await _settle();

    expect(provider.messages, isEmpty); // nothing was answered, nothing is kept
    expect(provider.error, isNull); // the limit sheet explains, not an error banner
    expect(provider.isStreaming, isFalse);
    expect(provider.isSendingMessage, isFalse);

    final limit = provider.takePlanLimit();
    expect(limit, isNotNull);
    expect(limit!.isLimitReached, isTrue);
    expect(limit.feature, 'chat');
    expect(provider.takePlanLimit(), isNull); // shown once
  });

  test('earlier messages stay when a later one is refused', () async {
    var calls = 0;
    final provider = ChatProvider(
      streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) {
        calls++;
        return calls == 1
            ? Stream<String>.fromIterable(['Hello ', 'there'])
            : Stream<String>.error(_limit());
      },
    );

    await provider.sendMessage('first');
    await _settle();
    expect(provider.messages.map((m) => m.content), ['first', 'Hello there']);

    await provider.sendMessage('second');
    await _settle();

    expect(provider.messages.map((m) => m.content), ['first', 'Hello there']);
    expect(provider.takePlanLimit(), isNotNull);
  });

  test('any other failure still shows an error and keeps the question', () async {
    final provider = ChatProvider(
      streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) =>
          Stream<String>.error(ApiException('The AI is busy.', statusCode: 503)),
    );

    await provider.sendMessage('hello');
    await _settle();

    expect(provider.error, 'The AI is busy.');
    expect(provider.takePlanLimit(), isNull);
    expect(provider.messages.length, 1);
    expect(provider.messages.single.role, MessageRole.user);
  });

  test('reset forgets a pending refusal', () async {
    final provider = ChatProvider(
      streamer: ({required message, chatHistory, responseStyle, mode = ChatMode.standard, onMeta}) =>
          Stream<String>.error(_limit()),
    );
    await provider.sendMessage('hello');
    await _settle();

    provider.reset();

    expect(provider.takePlanLimit(), isNull);
  });
}
