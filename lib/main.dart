import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/routes.dart';
import 'core/providers/theme_provider.dart';
import 'core/theme/theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
          initialRoute: AppRoutes.splash, // Updated initial route
          routes: AppRoutes.getRoutes(),
          onGenerateRoute: AppRoutes.generateRoute,
        );
      },
    );
  }
}
