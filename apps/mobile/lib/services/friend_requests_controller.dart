import 'package:flutter/foundation.dart';

import '../models/friend_request.dart';
import 'friends_service.dart';

/// Shared, refreshable state for incoming friendship requests.
///
/// Concurrent refreshes share one request. If any caller asks again while it
/// runs, exactly one additional request is made after the current one ends.
class FriendRequestsController extends ChangeNotifier {
  FriendRequestsController({required FriendsService friendsService})
    : _friendsService = friendsService;

  final FriendsService _friendsService;
  List<FriendRequest> _requests = const [];
  bool _isLoading = false;
  Object? _error;
  bool _disposed = false;
  bool _rerunQueued = false;
  Future<void>? _syncFuture;

  List<FriendRequest> get requests => _requests;
  bool get isLoading => _isLoading;
  Object? get error => _error;

  Future<void> refresh() {
    final running = _syncFuture;
    if (running != null) {
      _rerunQueued = true;
      return running;
    }

    final future = _runSyncLoop();
    _syncFuture = future;
    return future;
  }

  Future<void> _runSyncLoop() async {
    do {
      _rerunQueued = false;
      _isLoading = true;
      _error = null;
      _notify();

      try {
        _requests = List<FriendRequest>.unmodifiable(
          await _friendsService.getIncomingRequests(),
        );
      } catch (error) {
        _error = error;
      } finally {
        _isLoading = false;
        _notify();
      }
    } while (_rerunQueued && !_disposed);

    _syncFuture = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
