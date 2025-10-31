import 'package:flutter/material.dart';
import 'package:myapp/features/home/home_screen.dart';
import 'package:myapp/features/settings/settings_screen.dart';
import 'package:myapp/features/ticket_printing/tickets_history_screen.dart';
import 'package:myapp/features/ticket_validation/ticket_validator_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/core/constants/network_constants.dart';
import 'package:myapp/app/routes.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _currentIndex = 0;

  late final List<Widget> _pages = const [
    HomeScreen(),
    TicketsHistoryScreen(),
    TicketValidatorScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_outlined), label: 'Files'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Validate'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
        onTap: (i) async {
          if (i == 0) {
            setState(() => _currentIndex = i);
            return;
          }
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString(kAuthTokenKey);
          final isGuest = token == null || token.isEmpty;
          if (isGuest) {
            if (context.mounted) {
              Navigator.of(context).pushNamed(AppRoutes.login);
            }
            return;
          }
          setState(() => _currentIndex = i);
        },
      ),
    );
  }
}
