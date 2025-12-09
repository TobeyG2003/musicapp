import 'package:shared_preferences/shared_preferences.dart';

class SpotifyAuthService {
  static const String clientId = 'cff1856fb2e0491e9a639a6e5cad9821';
  static const String redirectUri = 'vibzcheck://callback';

  static const List<String> scopes = [
    'user-read-private',
    'user-read-email',
    'user-modify-playback-state',
    'user-read-playback-state',
    'user-read-currently-playing',
  ];

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;

  static final SpotifyAuthService _instance = SpotifyAuthService._internal();
  factory SpotifyAuthService() => _instance;
  SpotifyAuthService._internal();

  bool get isAuthenticated =>
      _accessToken != null && !_isTokenExpired();

  bool _isTokenExpired() {
    if (_tokenExpiry == null) return true;
    return DateTime.now().isAfter(_tokenExpiry!);
  }

  Future<void> initialize() async {
    await _loadTokens();
  }

  Future<bool> authenticate() async {
    try {
      // flutter_appauth is not available; OAuth would need to be handled differently
      // For now, return false to indicate authentication is not available
      print('[SpotifyAuthService] OAuth authentication not available');
      return false;
    } catch (e) {
      print('Spotify authentication error: $e');
      return false;
    }
  }

  Future<String?> getValidAccessToken() async {
    if (_accessToken == null) return null;

    if (_isTokenExpired() && _refreshToken != null) {
      await _refreshAccessToken();
    }

    return _accessToken;
  }

  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) return;

    try {
      // flutter_appauth is not available; token refresh would need custom implementation
      print('[SpotifyAuthService] Token refresh not available without OAuth');
    } catch (e) {
      print('Failed to refresh token: $e');
    }
  }

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_access_token');
    await prefs.remove('spotify_refresh_token');
    await prefs.remove('spotify_token_expiry');
  }

  Future<void> _loadTokens() async {
    final prefs = await SharedPreferences.getInstance();

    _accessToken = prefs.getString('spotify_access_token');
    _refreshToken = prefs.getString('spotify_refresh_token');

    final expiryString = prefs.getString('spotify_token_expiry');
    if (expiryString != null) {
      _tokenExpiry = DateTime.parse(expiryString);
    }
    
    print('[SpotifyAuthService] Loaded tokens - Access: ${_accessToken != null}, Refresh: ${_refreshToken != null}, Expiry: $_tokenExpiry');
  }
}
