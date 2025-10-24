import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/features/auth/login_screen.dart';
import 'package:myapp/features/checkout/sell_ticket_screen.dart';
import 'package:myapp/features/home/event_details_screen.dart';
import 'package:myapp/features/home/home_screen.dart';
import 'package:myapp/features/splash_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String eventDetails = '/event-details';
  static const String sellTicket = '/sell-ticket';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      splash: (context) => const SplashScreen(),
      login: (context) => const LoginScreen(),
      home: (context) => const HomeScreen(),
      sellTicket: (context) => const SellTicketScreen(),
    };
  }

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case sellTicket:
        return MaterialPageRoute(builder: (_) => const SellTicketScreen());
      case eventDetails:
        if (settings.arguments is Event) {
          final event = settings.arguments as Event;
          return MaterialPageRoute(
            builder: (_) => EventDetailsScreen(event: event),
          );
        }
        return _errorRoute();
      default:
        return _errorRoute();
    }
  }

   static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    // Handle routes that need arguments
    switch (settings.name) {
      case eventDetails:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (context) => const Placeholder(), // Replace with TicketDetailsScreen
        );
      default:
        return null;
    }
  }

  static Route<dynamic> _errorRoute() {
    return MaterialPageRoute(
      builder: (_) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Error'),
          ),
          body: const Center(
            child: Text('Page not found'),
          ),
        );
      },
    );
  }
}
