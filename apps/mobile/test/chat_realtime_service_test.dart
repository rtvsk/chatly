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
}
