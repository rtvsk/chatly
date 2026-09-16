import 'package:chatly/services/chat_realtime_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
// ignore: implementation_imports
import 'package:socket_io_client/src/manager.dart' as io_manager;

class _TestSocket extends io.Socket {
  _TestSocket()
    : super(
        io_manager.Manager(
          uri: 'http://localhost',
          options: {'autoConnect': false, 'reconnection': false},
        ),
        '/chats',
        const {},
      );

  int connectCalls = 0;
  int disconnectCalls = 0;
  int disposeCalls = 0;
  final List<String> emittedEvents = [];
  final List<dynamic> emittedPayloads = [];

  @override
  io.Socket connect() {
    connectCalls++;
    return this;
  }

  @override
  io.Socket disconnect() {
    disconnectCalls++;
    connected = false;
    return this;
  }

  @override
  void dispose() {
    disposeCalls++;
  }

  @override
  void emit(String event, [dynamic data]) {
    emittedEvents.add(event);
    emittedPayloads.add(data);
    notifyOutgoingListeners({
      'data': data == null ? [event] : [event, data],
    });
  }

  void triggerConnect() {
    connected = true;
    emitEvent(['connect', null]);
  }

  void triggerEvent(String event, dynamic payload) {
    emitEvent([event, payload]);
  }

  void triggerDisconnect() {
    connected = false;
    emitEvent(['disconnect', 'transport close']);
  }
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test('caches validated presence events and requests a snapshot', () async {
    final socket = _TestSocket();
    String? socketUri;
    final realtime = ChatRealtimeService(
      accessToken: () => 'access-token',
      socketFactory: (uri, _) {
        socketUri = uri;
        return socket;
      },
    );
    final updates = <Set<String>>[];
    final subscription = realtime.onlineUserIdsChanges.listen(updates.add);

    await realtime.connect();
    expect(socketUri, 'http://localhost:3000/chats');
    expect(socket.connectCalls, 1);

    socket.triggerConnect();
    expect(socket.emittedEvents, ['presence.get']);

    socket.triggerEvent('presence.snapshot', {
      'onlineUserIds': ['alice', 'bob', 'alice'],
    });
    await _flushEvents();
    expect(realtime.onlineUserIds, {'alice', 'bob'});
    expect(updates, [
      {'alice', 'bob'},
    ]);
    expect(() => realtime.onlineUserIds.add('mallory'), throwsUnsupportedError);
    expect(() => updates.single.add('mallory'), throwsUnsupportedError);

    socket.triggerEvent('presence.snapshot', {
      'onlineUserIds': ['alice', 7],
    });
    socket.triggerEvent('presence.changed', {'userId': 7, 'isOnline': true});
    socket.triggerEvent('presence.changed', {
      'userId': 'mallory',
      'isOnline': 'yes',
    });
    await _flushEvents();
    expect(realtime.onlineUserIds, {'alice', 'bob'});
    expect(updates, hasLength(1));

    socket.triggerEvent('presence.changed', {
      'userId': 'alice',
      'isOnline': false,
    });
    socket.triggerEvent('presence.changed', {
      'userId': 'mallory',
      'isOnline': true,
    });
    await _flushEvents();
    expect(realtime.onlineUserIds, {'bob', 'mallory'});
    expect(updates.last, {'bob', 'mallory'});

    await subscription.cancel();
  });

  test('handles outgoing events without a payload', () async {
    final socket = _TestSocket();
    final realtime = ChatRealtimeService(
      accessToken: () => 'access-token',
      socketFactory: (_, _) => socket,
    );

    await realtime.connect();
    socket.connected = true;

    expect(realtime.refreshPresence, returnsNormally);
    expect(socket.emittedEvents, ['presence.get']);
    expect(socket.emittedPayloads, [isNull]);
  });

  test(
    'clears and emits empty presence on socket loss and explicit disconnect',
    () async {
      final socket = _TestSocket();
      final realtime = ChatRealtimeService(
        accessToken: () => 'access-token',
        socketFactory: (_, _) => socket,
      );
      final updates = <Set<String>>[];
      final subscription = realtime.onlineUserIdsChanges.listen(updates.add);

      await realtime.connect();
      socket.triggerConnect();
      socket.triggerEvent('presence.snapshot', {
        'onlineUserIds': ['alice'],
      });
      await _flushEvents();

      socket.triggerDisconnect();
      await _flushEvents();
      expect(realtime.onlineUserIds, isEmpty);
      expect(updates.last, isEmpty);

      realtime.disconnect();
      await _flushEvents();
      expect(realtime.onlineUserIds, isEmpty);
      expect(updates.last, isEmpty);
      expect(socket.disconnectCalls, 1);
      expect(socket.disposeCalls, 1);
      expect(updates.where((update) => update.isEmpty), hasLength(2));

      await subscription.cancel();
    },
  );

  test(
    'publishes valid typing changes and emits typing state for a recipient',
    () async {
      final socket = _TestSocket();
      final realtime = ChatRealtimeService(
        accessToken: () => 'access-token',
        socketFactory: (_, _) => socket,
      );
      final changes = <TypingChangedEvent>[];
      final subscription = realtime.typingChanges.listen(changes.add);

      await realtime.connect();
      socket.triggerConnect();
      realtime.setTyping(recipientUserId: 'alice', isTyping: true);

      expect(socket.emittedEvents, ['presence.get', 'typing.set']);
      expect(socket.emittedPayloads.last, {
        'recipientUserId': 'alice',
        'isTyping': true,
      });

      socket.triggerEvent('typing.changed', {
        'userId': 'alice',
        'isTyping': true,
      });
      socket.triggerEvent('typing.changed', {'userId': 7, 'isTyping': true});
      socket.triggerEvent('typing.changed', {
        'userId': 'alice',
        'isTyping': 'yes',
      });
      socket.triggerEvent('typing.changed', const ['not-a-map']);
      await _flushEvents();

      expect(changes, hasLength(1));
      expect(changes.single.userId, 'alice');
      expect(changes.single.isTyping, isTrue);

      await subscription.cancel();
    },
  );

  test('publishes only validated friendship changes', () async {
    final socket = _TestSocket();
    final realtime = ChatRealtimeService(
      accessToken: () => 'access-token',
      socketFactory: (_, _) => socket,
    );
    final changes = <FriendshipChangedEvent>[];
    final subscription = realtime.friendshipChanges.listen(changes.add);

    await realtime.connect();
    socket.triggerConnect();
    socket.triggerEvent('friendship.changed', {'type': 'request_created'});
    socket.triggerEvent('friendship.changed', {'type': 'unknown'});
    socket.triggerEvent('friendship.changed', {'type': 7});
    socket.triggerEvent('friendship.changed', const ['not-a-map']);
    await _flushEvents();

    expect(changes, hasLength(1));
    expect(changes.single.type, FriendshipChangeType.requestCreated);
    await subscription.cancel();
  });

  test(
    'publishes valid read receipts and ignores malformed payloads',
    () async {
      final socket = _TestSocket();
      final realtime = ChatRealtimeService(
        accessToken: () => 'access-token',
        socketFactory: (_, _) => socket,
      );
      final reads = <MessageReadEvent>[];
      final subscription = realtime.messageReads.listen(reads.add);

      await realtime.connect();
      socket.triggerConnect();
      socket.triggerEvent('message.read', {
        'chatId': 'chat-id',
        'readerId': 'peer-id',
        'messageId': 'message-id',
        'messageCreatedAt': '2026-09-13T11:00:00.000Z',
      });
      socket.triggerEvent('message.read', {
        'chatId': 'chat-id',
        'readerId': 'peer-id',
        'messageId': 'message-id',
        'messageCreatedAt': 'not-a-date',
      });
      socket.triggerEvent('message.read', {
        'chatId': 'chat-id',
        'readerId': 7,
        'messageId': 'message-id',
        'messageCreatedAt': '2026-09-13T11:00:00.000Z',
      });
      socket.triggerEvent('message.read', const ['not-a-map']);
      await _flushEvents();

      expect(reads, hasLength(1));
      expect(reads.single.chatId, 'chat-id');
      expect(reads.single.readerId, 'peer-id');
      expect(reads.single.messageId, 'message-id');
      expect(reads.single.messageCreatedAt, DateTime.utc(2026, 9, 13, 11));

      await subscription.cancel();
    },
  );
}
