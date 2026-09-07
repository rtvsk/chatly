import 'dart:convert';

import '../models/friend_request.dart';
import 'api_service.dart';

class FriendsService {
  const FriendsService();

  Future<List<FriendRequest>> getIncomingRequests() async {
    final response = await ApiService.instance.get('/friends/requests');
    _requireSuccess(response.statusCode);

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => FriendRequest.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<FriendshipState> getFriendshipStatus(String userId) async {
    final response = await ApiService.instance.get('/friends/status/$userId');
    _requireSuccess(response.statusCode);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FriendshipState.fromJson(data['status'] as String);
  }

  Future<void> sendRequest(String receiverId) async {
    final response = await ApiService.instance.post(
      '/friends/request/$receiverId',
    );
    _requireSuccess(response.statusCode);
  }

  Future<void> acceptRequest(String friendshipId) async {
    final response = await ApiService.instance.post(
      '/friends/accept/$friendshipId',
    );
    _requireSuccess(response.statusCode);
  }

  Future<void> rejectRequest(String friendshipId) async {
    final response = await ApiService.instance.post(
      '/friends/reject/$friendshipId',
    );
    _requireSuccess(response.statusCode);
  }

  void _requireSuccess(int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception('Friendship request failed ($statusCode)');
    }
  }
}
