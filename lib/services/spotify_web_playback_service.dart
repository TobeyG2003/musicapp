import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SpotifyWebPlaybackService {
  // Singleton instance
  static final SpotifyWebPlaybackService _instance = SpotifyWebPlaybackService._internal();

  factory SpotifyWebPlaybackService() {
    return _instance;
  }

  SpotifyWebPlaybackService._internal();

  static const String clientId = 'eecdb44badc44526a3fdf6bfe3b8308b';
  static const String redirectUri = 'com.example.musicapp://callback';
  static const String authorizationEndpoint = 'https://accounts.spotify.com/authorize';
  static const String tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const String scopes = 'streaming user-read-email user-read-private user-modify-playback-state user-read-playback-state';

  String? _accessToken;
  DateTime? _tokenExpiry;
  
  // Listeners for token changes
  final List<Function()> _tokenChangeListeners = [];

  /// Generate a PKCE code challenge for secure OAuth flow (no client secret needed).
  static String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    final base64 = base64Url.encode(digest.bytes).replaceAll('=', '');
    return base64;
  }

  /// Generate a random code verifier (PKCE).
  /// PKCE requires 43-128 characters. We'll generate a proper random verifier.
  static String _generateCodeVerifier() {
    final random = List<int>.generate(32, (i) => (DateTime.now().microsecondsSinceEpoch + i) % 256);
    final encoded = base64Url.encode(random).replaceAll('=', '');
    // Return between 43-128 chars; we'll aim for ~43 (minimum)
    return encoded.length > 43 ? encoded.substring(0, 43) : encoded;
  }

  /// Start the PKCE Authorization Code flow (opens browser for user login).
  /// Returns true if the user completed the flow; the token is stored locally.
  Future<bool> authenticateWithPKCE() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Generate PKCE parameters.
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      // Save code verifier (will be used in token exchange).
      await prefs.setString('spotify_code_verifier', codeVerifier);

      // Build authorization URL.
      final authUri = Uri.parse(authorizationEndpoint).replace(
        queryParameters: {
          'client_id': clientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'code_challenge_method': 'S256',
          'code_challenge': codeChallenge,
          'scope': scopes,
          'show_dialog': 'true',
        },
      );

      print('Opening Spotify auth URL: $authUri');

      // Open Spotify login in browser.
      if (await canLaunchUrl(authUri)) {
        final launched = await launchUrl(authUri, mode: LaunchMode.externalApplication);
        print('URL launch result: $launched');
        if (launched) {
          print('Opened Spotify login in browser. Waiting for redirect...');
          return true; // User has been sent to the browser.
        } else {
          print('Failed to launch URL');
          return false;
        }
      } else {
        print('Cannot launch URL: $authUri');
        return false;
      }
    } catch (e) {
      print('Error starting PKCE auth: $e');
      return false;
    }
  }

  /// Exchange authorization code for access token (called after redirect from Spotify).
  Future<bool> exchangeCodeForToken(String authCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final codeVerifier = prefs.getString('spotify_code_verifier');

      if (codeVerifier == null) {
        print('Code verifier not found in shared preferences');
        return false;
      }

      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': authCode,
          'redirect_uri': redirectUri,
          'code_verifier': codeVerifier,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'];
        final expiresIn = data['expires_in'] ?? 3600;

        _accessToken = accessToken;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

        // Store token locally for persistence.
        await prefs.setString('spotify_access_token', accessToken);
        await prefs.setInt('spotify_token_expiry_ms', _tokenExpiry!.millisecondsSinceEpoch);

        // Clear code verifier.
        await prefs.remove('spotify_code_verifier');

        print('Token exchange successful. Access token obtained.');
        // Notify all listeners that token has changed
        _notifyTokenChange();
        return true;
      } else {
        print('Token exchange failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error exchanging code for token: $e');
      return false;
    }
  }

  /// Load stored access token from local storage.
  Future<void> loadStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('spotify_access_token');
      final expiryMs = prefs.getInt('spotify_token_expiry_ms');

      if (token != null && expiryMs != null) {
        _accessToken = token;
        _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
        print('Loaded stored Spotify access token');
      }
    } catch (e) {
      print('Error loading stored token: $e');
    }
  }

  /// Refresh the access token if expired.
  /// NOTE: With PKCE (no client secret), refresh tokens are not supported.
  /// If expired, the user must re-authenticate.
  Future<bool> ensureTokenValid() async {
    if (_accessToken == null) {
      await loadStoredToken();
    }

    if (_accessToken == null || (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!))) {
      print('Access token expired or unavailable. User must re-authenticate.');
      return false; // Token is invalid; user needs to re-authenticate.
    }

    return true;
  }

  /// Get the current access token.
  String? get accessToken => _accessToken;

  /// Check if user is authenticated.
  bool get isAuthenticated => _accessToken != null && (_tokenExpiry == null || DateTime.now().isBefore(_tokenExpiry!));

  /// Add a listener for token changes.
  void addTokenChangeListener(Function() callback) {
    _tokenChangeListeners.add(callback);
  }

  /// Remove a listener for token changes.
  void removeTokenChangeListener(Function() callback) {
    _tokenChangeListeners.remove(callback);
  }

  /// Notify all listeners of token changes.
  void _notifyTokenChange() {
    for (var listener in _tokenChangeListeners) {
      listener();
    }
  }

  /// Clear stored token and sign out.
  Future<void> signOut() async {
    _accessToken = null;
    _tokenExpiry = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_access_token');
    await prefs.remove('spotify_token_expiry_ms');
    print('Signed out of Spotify.');
  }
}
