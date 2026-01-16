import 'package:flutter/material.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:provider/provider.dart';
import 'app/routes.dart';
import 'core/providers/theme_provider.dart';
import 'core/theme/theme.dart';

// Global SyncService instance
final SyncService _syncService = SyncService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize automatic sync
  await _syncService.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Ticket Sales App',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeProvider.themeMode,
          debugShowCheckedModeBanner: false,
          initialRoute: AppRoutes.splash,
          routes: AppRoutes.getRoutes(),
          onGenerateRoute: AppRoutes.generateRoute,
        );
      },
    );
  }
}
