import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import '../models/avatar.dart';
import 'api_service.dart';

class AvatarService {
  const AvatarService();

  Future<List<Avatar>> getAvatars() async {
    final response = await ApiService.instance.get('/avatars');

    if (response.statusCode != 200) {
      throw Exception('Failed to load avatars (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map(Avatar.fromJson)
        .toList(growable: false);
  }

  Future<Avatar> uploadAvatar(XFile file) async {
    final response = await ApiService.instance.multipartPost(
      '/avatars',
      fieldName: 'file',
      bytes: await file.readAsBytes(),
      filename: file.name,
      mimeType: file.mimeType,
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to upload avatar (${response.statusCode})');
    }

    return Avatar.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> selectAvatar(String avatarId) async {
    final response = await ApiService.instance.patch(
      '/avatars/$avatarId/select',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to select avatar (${response.statusCode})');
    }
  }

  Future<void> deleteAvatar(String avatarId) async {
    final response = await ApiService.instance.delete('/avatars/$avatarId');

    if (response.statusCode != 200) {
      throw Exception('Failed to delete avatar (${response.statusCode})');
    }
  }
}
