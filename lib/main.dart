import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:musicapp/screens/Splash.dart';
import 'firebase_options.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app_links/app_links.dart';
import 'services/spotify_web_playback_service.dart';

const AUTH0_REDIRECT_URI = "com.musicapp://login-callback";


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  late SpotifyWebPlaybackService _spotifyService;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _spotifyService = SpotifyWebPlaybackService();
    _initializeDeepLinkListener();
  }

  void _initializeDeepLinkListener() {
    // Listen for deep links from Spotify OAuth redirect
    _appLinks.stringLinkStream.listen(
      (String link) {
        print('Deep link received: $link');
        _handleSpotifyAuthCallback(link);
      },
      onError: (err) {
        print('Deep link error: $err');
      },
    );
  }

  Future<void> _handleSpotifyAuthCallback(String link) async {
    try {
      final uri = Uri.parse(link);
      final authCode = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        print('Spotify auth error: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Spotify auth failed: $error')),
        );
        return;
      }

      if (authCode != null) {
        print('Spotify auth code received: $authCode');
        final success = await _spotifyService.exchangeCodeForToken(authCode);
        if (success) {
          print('Token exchange successful');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Spotify authentication successful!')),
          );
          // Trigger a rebuild of PartyScreen to update UI
          setState(() {});
        } else {
          print('Token exchange failed');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Token exchange failed')),
          );
        }
      }
    } catch (e) {
      print('Error handling Spotify auth callback: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Auth error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        scaffoldBackgroundColor: const Color.fromARGB(255, 39, 39, 39),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: Colors.white), 
          bodyLarge: TextStyle(color: Colors.white), 
          bodyMedium: TextStyle(color: Colors.white),
          labelSmall: TextStyle(color: Colors.white),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(
            color: Color.fromARGB(255, 131, 53, 233),
          ),
          floatingLabelStyle: TextStyle(
            color: Color.fromARGB(255, 98, 39, 176), // Color for the label when floating
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color.fromARGB(255, 131, 53, 233)),
            borderRadius: BorderRadius.all(Radius.circular(5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color.fromARGB(255, 131, 53, 233), width: 2.0),
            borderRadius: BorderRadius.all(Radius.circular(25)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 98, 39, 176),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 16),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        useMaterial3: true,
        fontFamily: GoogleFonts.poppins().fontFamily,
      ),
      home: const Splash(title: 'Vibcheckz'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            
          ],
        ),
      ),
    );
  }
}
