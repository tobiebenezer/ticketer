import 'package:flutter/material.dart';
import 'package:myapp/data/services/api_service.dart';
import 'package:myapp/data/services/post_login_sync_service.dart';
import 'package:myapp/app/routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authApi = AuthApi();
  final _postLoginSync = PostLoginSyncService();
  bool _isLoading = false;
  bool _isSyncing = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final result = await _authApi.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        // Login successful, trigger post-login sync
        setState(() {
          _isLoading = false;
          _isSyncing = true;
        });

        final syncResult = await _postLoginSync.syncAfterLogin();

        if (!mounted) return;

        setState(() {
          _isSyncing = false;
        });

        // Show sync result
        if (syncResult.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Synced: ${syncResult.summary}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        // Navigate to home
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      } else {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Invalid username or password',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _guestLogin() {
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Image.asset(
                  'assets/images/Plateau_United.png',
                  width: 80.0,
                  height: 80.0,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24.0),
                Text(
                  'Welcome Back',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8.0),
                Text(
                  'Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32.0),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32.0),
                _isLoading || _isSyncing
                    ? Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16.0),
                          Text(
                            _isSyncing
                                ? 'Syncing offline data...'
                                : 'Logging in...',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                    : ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text('Login'),
                      ),
                const SizedBox(height: 16.0),
                TextButton(
                  onPressed: _guestLogin,
                  child: const Text('Continue as Guest'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
