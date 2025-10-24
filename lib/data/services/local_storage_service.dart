import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/data/models/event_model.dart';

class LocalStorageService {
  static const String _eventsKey = 'events';

  Future<void> cacheEvents(List<Event> events) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> encodedEvents = events
        .map((event) => jsonEncode(event.toJson()))
        .toList();
    await prefs.setStringList(_eventsKey, encodedEvents);
  }

  Future<List<Event>> getCachedEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedEvents = prefs.getStringList(_eventsKey);
    if (encodedEvents == null) {
      return [];
    }
    return encodedEvents
        .map((encodedEvent) => Event.fromJson(jsonDecode(encodedEvent)))
        .toList();
  }
}
