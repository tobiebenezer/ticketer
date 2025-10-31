import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/features/auth/login_screen.dart';
import 'package:myapp/features/checkout/sell_ticket_screen.dart';
import 'package:myapp/features/home/event_details_screen.dart';
import 'package:myapp/features/home/main_nav_screen.dart';
import 'package:myapp/features/ticket_printing/tickets_history_screen.dart';
import 'package:myapp/features/settings/settings_screen.dart';
import 'package:myapp/features/splash_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String eventDetails = '/event-details';
  static const String sellTicket = '/sell-ticket';
  static const String ticketsHistory = '/tickets-history';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      splash: (context) => const SplashScreen(),
      login: (context) => const LoginScreen(),
      home: (context) => const MainNavScreen(),
      ticketsHistory: (context) => const TicketsHistoryScreen(),
      settings: (context) => const SettingsScreen(),
    };
  }

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case home:
        return MaterialPageRoute(builder: (_) => const MainNavScreen());
      case ticketsHistory:
        return MaterialPageRoute(builder: (_) => const TicketsHistoryScreen());
      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case sellTicket:
        if (settings.arguments is Map<String, dynamic>) {
          final args = settings.arguments as Map<String, dynamic>;
          final event = args['event'];
          final ticketType = args['ticketType'];
          if (event is Event && ticketType is TicketType) {
            return MaterialPageRoute(
              builder: (_) => SellTicketScreen(event: event, ticketType: ticketType),
            );
          }
        }
        return _errorRoute();
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
