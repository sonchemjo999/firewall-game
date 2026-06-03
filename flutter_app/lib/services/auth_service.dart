import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  String? _token;
  String? _username;
  String? _role;
  String? _planSlug;
  String? _planName;
  bool _isLoggedIn = false;

  bool get isLoggedIn => _isLoggedIn;
  String? get token => _token;
  String? get username => _username;
  String? get role => _role;
  String? get planSlug => _planSlug;
  String? get planName => _planName;
  bool get isAdmin => _role == 'admin';
  bool get isReseller => _role == 'reseller' || isAdmin;
  bool get isPremium => _role == 'premium' || isReseller;

  AuthService() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _username = prefs.getString('username');
    _role = prefs.getString('role');
    _planSlug = prefs.getString('plan_slug');
    _planName = prefs.getString('plan_name');
    _isLoggedIn = _token != null;
    notifyListeners();
  }

  Future<void> login(String token, String username, String role,
      {String? planSlug, String? planName}) async {
    _token = token;
    _username = username;
    _role = role;
    _planSlug = planSlug;
    _planName = planName;
    _isLoggedIn = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    await prefs.setString('role', role);
    if (planSlug != null) await prefs.setString('plan_slug', planSlug);
    if (planName != null) await prefs.setString('plan_name', planName);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    _role = null;
    _planSlug = null;
    _planName = null;
    _isLoggedIn = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }
}
