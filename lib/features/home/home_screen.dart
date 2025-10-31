import 'package:flutter/material.dart';
import 'package:myapp/core/providers/theme_provider.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:myapp/data/services/local_storage_service.dart';
import 'package:myapp/features/home/event_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/core/constants/network_constants.dart';
import 'package:myapp/app/routes.dart';
import 'package:myapp/data/services/api_client.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final EventApi _eventApi = EventApi();
  final LocalStorageService _localStorageService = LocalStorageService();
  List<Event> _events = [];
  List<Event> _filteredEvents = [];
  bool _isLoading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  bool _isGuest = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _searchController.addListener(_filterEvents);
    _loadAuthState();

    // Set up global 401 handler to redirect to login
    ApiClient.onUnauthorized = () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(kAuthTokenKey);
      } catch (_) {}
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      }
    };
  }

  Future<void> _loadAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(kAuthTokenKey);
      if (!mounted) return;
      setState(() {
        _isGuest = token == null || token.isEmpty;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterEvents);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEvents({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<Event> events;
      if (!forceRefresh) {
        events = await _localStorageService.getCachedEvents();
        if (events.isNotEmpty) {
          _setEvents(events);
          return;
        }
      }

      events = await _eventApi.getEvents();
      await _localStorageService.cacheEvents(events);
      _setEvents(events);
    } catch (e) {
      setState(() {
        _error = 'Failed to load events. Please try again later.';
        _isLoading = false;
      });
    }
  }

  void _setEvents(List<Event> events) {
    setState(() {
      _events = events;
      _filteredEvents = events;
      _isLoading = false;
    });
  }

  void _filterEvents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEvents = _events.where((event) {
        final categoryMatches = _selectedCategory == 'All' ||
            event.status.toLowerCase() == _selectedCategory.toLowerCase();
        final title = '${event.homeTeam} vs ${event.awayTeam}'.toLowerCase();
        final searchMatches =
            title.contains(query) ||
            event.venue.toLowerCase().contains(query) ||
            event.competition.toLowerCase().contains(query);
        return categoryMatches && searchMatches;
      }).toList();
    });
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
      _filterEvents();
    });
  }

  void _navigateToDetails(Event event) {
    if (_isGuest) {
      Navigator.of(context).pushNamed(AppRoutes.login);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Matches'),
        actions: [
          _isGuest
              ? IconButton(
                  icon: const Icon(Icons.login),
                  tooltip: 'Login',
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.login).then((_) => _loadAuthState());
                  },
                )
              : IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Logout'),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove(kAuthTokenKey);
                      } catch (_) {}
                      if (mounted) {
                        setState(() => _isGuest = true);
                        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
                      }
                    }
                  },
                ),
          Switch(
            value: themeProvider.themeMode == ThemeMode.dark,
            onChanged: (value) {
              themeProvider.toggleTheme();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadEvents(forceRefresh: true),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search events...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
              ),
            ),
            _buildFilterChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final categories = ['All', 'upcoming', 'played', 'postponed', 'cancelled'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Wrap(
        spacing: 8.0,
        children: categories.map((category) {
          return ChoiceChip(
            label: Text(category),
            selected: _selectedCategory == category,
            onSelected: (selected) {
              if (selected) {
                _onCategorySelected(category);
              }
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_filteredEvents.isEmpty) {
      return const Center(child: Text('No events found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _filteredEvents.length,
      itemBuilder: (context, index) {
        final event = _filteredEvents[index];
        return GestureDetector(
          onTap: () => _navigateToDetails(event),
          child: Card(
            elevation: 4.0,
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12.0),
                    topRight: Radius.circular(12.0),
                  ),
                  child: Image.asset(
                    'assets/images/event_art.jpg',
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${event.homeTeam} vs ${event.awayTeam}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16.0),
                          const SizedBox(width: 8.0),
                          Text(
                            event.matchDate,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4.0),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16.0),
                          const SizedBox(width: 8.0),
                          Text(
                            event.venue,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
