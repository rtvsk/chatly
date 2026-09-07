import 'dart:convert';

import '../models/contact.dart';
import 'api_service.dart';

class ContactsService {
  const ContactsService();

  Future<List<Contact>> getFriends() async {
    final response = await ApiService.instance.get('/friends');
    return _decodeContacts(response.statusCode, response.body);
  }

  Future<List<Contact>> searchUsers(String login) async {
    final encodedLogin = Uri.encodeQueryComponent(login.trim());
    final response = await ApiService.instance.get(
      '/users/search?login=$encodedLogin',
    );
    return _decodeContacts(response.statusCode, response.body);
  }

  List<Contact> _decodeContacts(int statusCode, String body) {
    if (statusCode != 200) {
      throw Exception('Failed to load contacts ($statusCode)');
    }

    final data = jsonDecode(body) as List<dynamic>;
    return data
        .map((item) => Contact.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }
}
