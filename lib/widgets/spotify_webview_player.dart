import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A widget that loads Spotify Web Playback SDK and provides playback controls.
/// The SDK is loaded in a webview and communicates via JS messages.
class SpotifyWebPlaybackPlayer extends StatefulWidget {
  final String accessToken;
  final String? trackUri;
  final Function(String message)? onPlayerStateChanged;
  final Function(bool isReady)? onPlayerReady;

  const SpotifyWebPlaybackPlayer({
    Key? key,
    required this.accessToken,
    this.trackUri,
    this.onPlayerStateChanged,
    this.onPlayerReady,
  }) : super(key: key);

  @override
  State<SpotifyWebPlaybackPlayer> createState() => _SpotifyWebPlaybackPlayerState();
}

class _SpotifyWebPlaybackPlayerState extends State<SpotifyWebPlaybackPlayer> {
  late WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    // HTML content with embedded JavaScript for Spotify Web Playback SDK
    final token = widget.accessToken;
    final htmlContent = _buildHtmlContent(token);

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('Page started: $url');
          },
          onPageFinished: (String url) {
            print('Page finished loading');
          },
        ),
      )
      ..addJavaScriptChannel(
        'flutter_inappwebview',
        onMessageReceived: (JavaScriptMessage message) {
          final data = message.message;
          print('JS Message: $data');
          
          // Check if this is a player ready event
          if (data == 'Connected') {
            print('Player is ready!');
            if (widget.onPlayerReady != null) {
              widget.onPlayerReady!(true);
            }
          } else if (widget.onPlayerStateChanged != null) {
            widget.onPlayerStateChanged!(data);
          }
        },
      )
      ..loadHtmlString(htmlContent);
  }

  String _buildHtmlContent(String token) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Spotify Player</title>
    <script src="https://sdk.scdn.co/spotify-player.js"></script>
    <style>
        body { margin: 0; padding: 0; background-color: #191414; }
    </style>
</head>
<body>
    <script>
        window.onSpotifyWebPlaybackSDKReady = () => {
            const token = "$token";
            console.log("SDK ready, initializing player...");

            const player = new Spotify.Player({
                name: "Flutter Music App",
                getOAuthToken: cb => { cb(token); },
                volume: 0.5
            });

            window.spotifyPlayer = player;
            window.playerConnected = false;

            player.addListener("player_state_changed", state => {
                if (state) {
                    console.log("Player state changed:", state);
                    const message = JSON.stringify({
                        is_playing: !state.paused,
                        current_track: state.track_window.current_track.name,
                        position_ms: state.position,
                        duration_ms: state.duration
                    });
                    window.flutter_inappwebview.callHandler("onPlayerStateChanged", message);
                }
            });

            player.addListener("initialization_error", ({ message }) => {
                console.error("Failed to initialize", message);
            });

            player.addListener("authentication_error", ({ message }) => {
                console.error("Failed to authenticate", message);
            });

            player.addListener("account_error", ({ message }) => {
                console.error("Failed to validate account status", message);
            });

            player.connect().then(success => {
                if (success) {
                    console.log("Connected to Spotify!");
                    window.playerConnected = true;
                    window.flutter_inappwebview.callHandler("onPlayerReady", "Connected");
                } else {
                    console.error("Failed to connect to Spotify player");
                }
            });
        };

        window.playTrack = (spotifyUri) => {
            console.log("playTrack called with:", spotifyUri);
            if (window.spotifyPlayer && window.playerConnected) {
                window.spotifyPlayer.play({spotify_uri: spotifyUri}).then(() => {
                    console.log("Playing: " + spotifyUri);
                }).catch(err => {
                    console.error("Play error:", err);
                });
            } else {
                console.error("Player not ready. Connected:", window.playerConnected, "Player exists:", !!window.spotifyPlayer);
            }
        };

        window.pauseTrack = () => {
            if (window.spotifyPlayer) {
                window.spotifyPlayer.pause();
            }
        };

        window.resumeTrack = () => {
            if (window.spotifyPlayer) {
                window.spotifyPlayer.resume();
            }
        };

        window.seekToPosition = (positionMs) => {
            if (window.spotifyPlayer) {
                window.spotifyPlayer.seek(positionMs);
            }
        };
    </script>
</body>
</html>
    ''';
  }

  @override
  void didUpdateWidget(SpotifyWebPlaybackPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackUri != widget.trackUri && widget.trackUri != null) {
      playTrack(widget.trackUri!);
    }
  }

  void playTrack(String spotifyUri) {
    _webViewController.runJavaScript("window.playTrack(\"$spotifyUri\");");
  }

  void pauseTrack() {
    _webViewController.runJavaScript("window.pauseTrack();");
  }

  void resumeTrack() {
    _webViewController.runJavaScript("window.resumeTrack();");
  }

  void seekTo(int positionMs) {
    _webViewController.runJavaScript("window.seekToPosition($positionMs);");
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _webViewController);
  }
}
