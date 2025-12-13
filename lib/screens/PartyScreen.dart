import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:async';
import 'drawer.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/spotify_web_playback_service.dart';
import '../services/spotify_auth_service.dart';

String clientid = "eecdb44badc44526a3fdf6bfe3b8308b";
String secretClient = "977979869e7a48d9bbc8e1478c953ae3";


class Partyscreen extends StatefulWidget {
  const Partyscreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<Partyscreen> createState() => _PartyScreen();
}

class _PartyScreen extends State<Partyscreen> with TickerProviderStateMixin {
    StreamSubscription<QuerySnapshot>? _queueToVotesSubscription;
  late TabController _tabController;
  StreamSubscription<QuerySnapshot>? _queueSubscription;
  String? _currentlyPlayingUri;
  Timer? _playbackCheckTimer;
  final SpotifyAuthService _spotifyAuth = SpotifyAuthService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _spotifyAuth.initialize();
    _setupAutoplay();

    // Listen to queue and sync top 3 to votes/song1-3
    _queueToVotesSubscription = FirebaseFirestore.instance
        .collection('lobbies')
        .doc(widget.roomId)
        .collection('queue')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) async {
      final top3 = snapshot.docs.take(3).toList();
      final votesRef = FirebaseFirestore.instance
          .collection('lobbies')
          .doc(widget.roomId)
          .collection('votes');

      for (int i = 0; i < 3; i++) {
        final docId = 'song${i + 1}';
        if (i < top3.length) {
          final song = top3[i].data() as Map<String, dynamic>;
          await votesRef.doc(docId).set({
            'artist': song['artist'],
            'imageUrl': song['imageUrl'],
            'name': song['name'],
            'uri': song['uri'],
            'votenum': song['votenum'] ?? 0,
            'songid': top3[i].id,
          });
        } else {
          // Clear the doc if not enough songs
          await votesRef.doc(docId).set({
            'artist': null,
            'imageUrl': null,
            'name': null,
            'uri': null,
            'votenum': 0,
          });
        }
      }
    });
  } 
  void _setupAutoplay() { // beginning of auto play feature
    FirebaseFirestore.instance
        .collection('lobbies')
        .doc(widget.roomId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        bool votingEnabled = snapshot.data()?['votingEnabled'] ?? false;
        
        if (!votingEnabled && _queueSubscription == null) {
          _startAutoplay();
        } else if (votingEnabled && _queueSubscription != null) {
          _stopAutoplay();
        }
      }
    });
  }

  void _startAutoplay() {
    print('Autoplay started - monitoring queue and playback');
    
    // check playback status every 3 seconds
    _playbackCheckTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      await _checkAndPlayNext();
    });
  }

  Future<void> _playTopVotedSong() async {
    try {
      // get top voted song from votes collection
      final votesSnapshot = await FirebaseFirestore.instance
          .collection('lobbies')
          .doc(widget.roomId)
          .collection('votes')
          .orderBy('votenum', descending: true)
          .limit(1)
          .get();

      if (votesSnapshot.docs.isEmpty) {
        print('No songs in votes');
        _currentlyPlayingUri = null;
        return;
      }

      var topSongDoc = votesSnapshot.docs.first;
      Map<String, dynamic> song = topSongDoc.data() as Map<String, dynamic>;
      String uri = song['uri'] ?? '';
      if (uri.isEmpty) return;

      // only play if it's different from what was playing
      if (uri != _currentlyPlayingUri) {
        print('Playing top voted song: ${song['name']}');
        bool success = await _playOnSpotify(uri, song);
        if (success) {
          _currentlyPlayingUri = uri;
          await _addToHistoryFromAutoplay(song, widget.roomId);
          // Optionally, you could reset votes here or remove the song from votes
        }
      }
    } catch (e) {
      print('Play top voted error: $e');
    }
  }

  Future<void> _checkAndPlayNext() async {
    try {
      final accessToken = await _spotifyAuth.getValidAccessToken();
      if (accessToken == null) return;

      // check what's currently playing
      final playbackResponse = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      bool isPlaying = false;
      String? currentTrackUri;

      if (playbackResponse.statusCode == 200) {
        final playbackData = jsonDecode(playbackResponse.body);
        isPlaying = playbackData['is_playing'] ?? false;
        currentTrackUri = playbackData['item']?['uri'];
      }

      // if nothing is playing or song finished, play top voted song
      if (!isPlaying || currentTrackUri == null) {
        print('Nothing playing - checking votes for top song');
        await _playTopVotedSong();
      } else {
        print('Currently playing: $currentTrackUri');
        _currentlyPlayingUri = currentTrackUri;
      }
    } catch (e) {
      print('Playback check error: $e');
    }
  }

  Future<void> _playNextFromQueue() async {
    try {
      // get first song from queue
      final queueSnapshot = await FirebaseFirestore.instance
          .collection('lobbies')
          .doc(widget.roomId)
          .collection('queue')
          .orderBy('timestamp', descending: false)
          .limit(1)
          .get();

      if (queueSnapshot.docs.isEmpty) {
        print('Queue is empty');
        _currentlyPlayingUri = null;
        return;
      }

      var firstSong = queueSnapshot.docs.first;
      Map<String, dynamic> song = firstSong.data() as Map<String, dynamic>;
      String uri = song['uri'] ?? '';

      if (uri.isEmpty) return;

      // only play if it's different from what was playing
      if (uri != _currentlyPlayingUri) {
        print('Playing next from queue: ${song['name']}');
        
        bool success = await _playOnSpotify(uri, song);
        
        if (success) {
          _currentlyPlayingUri = uri;
          await _addToHistoryFromAutoplay(song, widget.roomId);
          // remove from queue after starting playback
          await firstSong.reference.delete();
        }
      }
    } catch (e) {
      print('Play next error: $e');
    }
  }

  void _stopAutoplay() {
    print('Autoplay stopped');
    _playbackCheckTimer?.cancel();
    _playbackCheckTimer = null;
    _queueSubscription?.cancel();
    _queueSubscription = null;
  }

  Future<bool> _playOnSpotify(String uri, Map<String, dynamic> song) async {
    try {
      final accessToken = await _spotifyAuth.getValidAccessToken();
      if (accessToken == null) {
        print('No access token available');
        return false;
      }

      final response = await http.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'uris': [uri]}),
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        print('✓ Playing: ${song['name']}');
        return true;
      } else if (response.statusCode == 404) {
        print('✗ No active Spotify device found');
        return false;
      } else {
        print('✗ Playback failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Playback error: $e');
      return false;
    }
  }

  Future<void> _addToHistoryFromAutoplay(Map<String, dynamic> song, String roomId) async {
    try {
      await FirebaseFirestore.instance
          .collection('lobbies')
          .doc(roomId)
          .collection('history')
          .add({
        'name': song['name'],
        'artist': song['artist'],
        'uri': song['uri'],
        'imageUrl': song['imageUrl'],
        'playedAt': Timestamp.now(),
      });
    } catch (e) {
      print('History error: $e');
    }
  }

  @override
  void dispose() {
    _stopAutoplay();
    _queueToVotesSubscription?.cancel();
    _tabController.dispose();
    super.dispose(); // end of autoplay feature
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 98, 39, 176),
        title: Text('Room - ${widget.roomId}', style: TextStyle(color: Colors.white,)),
      ),
      drawer: appbarDrawer(),
            bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color.fromARGB(255, 98, 39, 176),
        currentIndex: _tabController.index,
        onTap: (index) {
          setState(() {
            _tabController.animateTo(index);
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.white,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Song'),
          BottomNavigationBarItem(icon: Icon(Icons.queue_music), label: 'Queue'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SongScreen(roomId: widget.roomId),
          QueueScreen(roomId: widget.roomId),
          ChatScreen(roomId: widget.roomId),
          HistoryScreen(roomId: widget.roomId),
        ]
      ),
    );
  }
}

class SongScreen extends StatefulWidget {
  final String roomId;
  
  const SongScreen({super.key, required this.roomId});

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
    bool _isSearching = false;
  String? _currentTrackName;
  String? _accessToken;
  DateTime? _tokenExpiry;
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  late SpotifyWebPlaybackService _spotifyWebService;

  void showVotingDialog() {
    final votesRef = FirebaseFirestore.instance
        .collection('lobbies')
        .doc(widget.roomId)
        .collection('votes');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 30, 30, 30),
          title: Text('Voting', style: TextStyle(color: Colors.white)),
          content: FutureBuilder<List<DocumentSnapshot>>(
            future: Future.wait([
              votesRef.doc('song1').get(),
              votesRef.doc('song2').get(),
              votesRef.doc('song3').get(),
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null || data['name'] == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey[800],
                            child: Icon(Icons.music_note, color: Colors.white, size: 40),
                          ),
                          SizedBox(height: 8),
                          Text('No Song', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: data['name'] == null ? null : () async {
                            // Atomically increment vote count in Firestore
                            await votesRef.doc('song${i + 1}').update({
                              'votenum': FieldValue.increment(1),
                            });
                            Navigator.of(context).pop();
                          },
                          child: data['imageUrl'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    data['imageUrl'],
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.grey[800],
                                  child: Icon(Icons.music_note, color: Colors.white, size: 40),
                                ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          data['name'] ?? '',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          data['artist'] ?? '',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text('Votes: ${data['votenum'] ?? 0}', style: TextStyle(color: Colors.deepPurpleAccent)),
                      ],
                    ),
                  );
                }),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('No vote', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _spotifyWebService = SpotifyWebPlaybackService();
    _audioPlayer = AudioPlayer();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });
    // Load stored Spotify token
    _initializeSpotifyAuth();
    // Get Spotify API access token for search (client credentials)
    _getAccessToken();
    // Listen for token changes from the service
    _spotifyWebService.addTokenChangeListener(_onSpotifyTokenChanged);
  }

  void _onSpotifyTokenChanged() {
    print('Spotify token changed, rebuilding PartyScreen');
    setState(() {});
  }

  Future<void> _initializeSpotifyAuth() async {
    await _spotifyWebService.loadStoredToken();
    setState(() {});
  }

  Future<void> _getAccessToken() async {
    try {
      final credentials = base64.encode(utf8.encode('$clientid:$secretClient'));
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _accessToken = data['access_token'];
          _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in'] ?? 3600));
        });
        print('Spotify access token obtained successfully');
      } else {
        print('Failed to get access token: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting access token: $e');
    }
  }

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }


    setState(() => _isSearching = true);

    try {
      // Ensure we have a valid token
      if (_accessToken == null || (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!))) {
        await _getAccessToken();
      }

      if (_accessToken == null) {
        throw Exception('Failed to obtain Spotify access token');
      }

      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/search').replace(
          queryParameters: {
            'q': query,
            'type': 'track',
            'limit': '20',
          },
        ),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracks = data['tracks']['items'] as List;

        setState(() {
          _searchResults = tracks.map((track) {
            return {
              'name': track['name'] ?? 'Unknown',
              'artist': (track['artists'] as List?)?.isNotEmpty == true
                  ? track['artists'][0]['name'] ?? 'Unknown Artist'
                  : 'Unknown Artist',
              'artistId': (track['artists'] as List?)?.isNotEmpty == true
                  ? track['artists'][0]['id']
                  : null,
              'uri': track['uri'] ?? '',
              'id': track['id'],
              'previewUrl': track['preview_url'],
              'imageUrl': (track['album']['images'] as List?)?.isNotEmpty == true
                  ? track['album']['images'][0]['url']
                  : null,
            };
          }).toList();
        });
      
        await _enrichTracksWithMetadata();
        print('Found ${_searchResults.length} songs');

      } else if (response.statusCode == 401) {
        print('Unauthorized - attempting to refresh token');
        await _getAccessToken();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Token refreshed - try searching again')),
        );
      } else {
        print('Search error: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: ${response.statusCode}')),
        );
      }
    } catch (e) {
      print('Search error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching songs: $e')),
      );
    } finally {
      setState(() => _isSearching = false);
    }
  }
  Future<void> _enrichTracksWithMetadata() async {
    if (_accessToken == null || _searchResults.isEmpty) return;

    try {
      // Get track IDs
      final trackIds = _searchResults
          .where((t) => t['id'] != null)
          .map((t) => t['id'] as String)
          .toList();
      
      if (trackIds.isEmpty) return;

      setState(() {});
    } catch (e) {
      print('Error enriching tracks: $e');
    }
  }

  Future<void> _fetchAudioFeatures(List<String> trackIds) async {
    try {
      // Spotify allows up to 100 IDs per request
      final batches = <List<String>>[];
      for (var i = 0; i < trackIds.length; i += 100) {
        batches.add(trackIds.sublist(
          i, 
          i + 100 > trackIds.length ? trackIds.length : i + 100
        ));
      }

      for (var batch in batches) {
        final response = await http.get(
          Uri.parse('https://api.spotify.com/v1/audio-features').replace(
            queryParameters: {'ids': batch.join(',')},
          ),
          headers: {'Authorization': 'Bearer $_accessToken'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final features = data['audio_features'] as List;
          
          for (var feature in features) {
            if (feature == null) continue;
            
            final trackId = feature['id'];
            
          }
        }
      }
    } catch (e) {
      print('Error fetching audio features: $e');
    }
  }

  
  Future<void> _playSong(String uri, String name, String? previewUrl) async {
    print('Playing song: $name, uri: $uri');
    try {
      // On Android, Web Playback SDK doesn't work in webview
      // So we'll open the Spotify app to play the full track
      final trackId = uri.split(':').last;
      
      // Try to open in Spotify app first
      final spotifyAppUri = Uri.parse('spotify:track:$trackId');
      if (await canLaunchUrl(spotifyAppUri)) {
        await launchUrl(spotifyAppUri, mode: LaunchMode.externalApplication);
        setState(() {
          _currentTrackName = name;
        });
        await _addToHistory({
          'name': name,
          'artist': _searchResults.firstWhere((t) => t['uri'] == uri, orElse: () => {})['artist'] ?? 'Unknown',
          'uri': uri,
          'imageUrl': _searchResults.firstWhere((t) => t['uri'] == uri, orElse: () => {})['imageUrl'],
        }, widget.roomId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playing in Spotify app: $name')),
        );
        return;
      }

      // Fallback: open in Spotify Web
      final spotifyWebUrl = Uri.parse('https://open.spotify.com/track/$trackId');
      if (await canLaunchUrl(spotifyWebUrl)) {
        await launchUrl(spotifyWebUrl, mode: LaunchMode.externalApplication);
        setState(() {
          _currentTrackName = name;
        });
        await _addToHistory({
          'name': name,
          'artist': _searchResults.firstWhere((t) => t['uri'] == uri, orElse: () => {})['artist'] ?? 'Unknown',
          'uri': uri,
          'imageUrl': _searchResults.firstWhere((t) => t['uri'] == uri, orElse: () => {})['imageUrl'],
        }, widget.roomId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening in Spotify Web: $name')),
        );
        return;
      }

      // Last fallback: play preview in-app
      if (previewUrl != null && previewUrl.isNotEmpty) {
        await _playPreview(previewUrl, name);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot play - no preview available')),
        );
      }
    } catch (e) {
      print('Error playing song: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing song: $e')),
      );
    }
  }
  


  Future<void> _authenticateWithSpotify() async {
    print('Attempting to authenticate with Spotify...');
    final success = await _spotifyWebService.authenticateWithPKCE();
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✓ Spotify login opened in browser - complete login and return to the app')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✗ Failed to open Spotify login')),
      );
    }
  }

  Future<void> _playPreview(String previewUrl, String name) async {
    try {
      if (_isPlaying) {
        await _audioPlayer.stop();
      }
      await _audioPlayer.play(UrlSource(previewUrl));
      setState(() {
        _currentTrackName = '$name (30s Preview)';
      });
      await _addToHistory({
        'name': name.replaceAll(' (30s Preview)', ''),
        'artist': 'Unknown',
        'uri': '',
        'imageUrl': null,
      }, widget.roomId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playing preview: $name')),
      );
    } catch (e) {
      print('Preview play error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play preview: $e')),
      );
    }
  }
  Future<void> _addToHistory(Map<String, dynamic> songData, String roomId) async {
    try {
      await FirebaseFirestore.instance
          .collection('lobbies')
          .doc(roomId)
          .collection('history')
          .add({
        'name': songData['name'],
        'artist': songData['artist'],
        'uri': songData['uri'],
        'imageUrl': songData['imageUrl'],
        'playedAt': Timestamp.now(),
      });
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('history')
          .add({
        'name': songData['name'],
        'artist': songData['artist'],
        'uri': songData['uri'],
        'imageUrl': songData['imageUrl'],
        'playedAt': Timestamp.now(),
      });
      print('Added to history: ${songData['name']}');
    } catch (e) {
      print('Error adding to history: $e');
    }
  }
  @override
  void dispose() {
    _spotifyWebService.removeTokenChangeListener(_onSpotifyTokenChanged);
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(onPressed: () {showVotingDialog();}, child: Text('test')),
            Text('Search & Play Songs', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Authentication button if not authenticated
            if (!_spotifyWebService.isAuthenticated)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Login with Spotify',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _authenticateWithSpotify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Authenticate with Spotify'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in with Spotify Premium to play full tracks',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '✓ Connected to Spotify',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 16),
            // Current song display
            if (_currentTrackName != null) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text('Now Playing', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    SizedBox(height: 8),
                    Text(
                      _currentTrackName!,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.deepPurple),
                          onPressed: () async {
                            if (_isPlaying) {
                              await _audioPlayer.pause();
                            } else {
                              await _audioPlayer.resume();
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.stop, color: Colors.deepPurple),
                          onPressed: () async {
                            await _audioPlayer.stop();
                            setState(() => _currentTrackName = null);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],
            // Search bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search for a song...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: _searchSongs,
            ),
            SizedBox(height: 16),

            if (_searchResults.isNotEmpty) ...[
              SizedBox(height: 16),
          ],

          if (_isSearching)
            CircularProgressIndicator()
          else if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
            Text(_searchResults.isEmpty 
              ? 'No songs found' 
              : 'No songs match selected filters')
          else if (_searchResults.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final track = _searchResults[index];
                final trackId = track['id'];

                return GestureDetector(
                  onTap: () => _playSong(track['uri'], track['name'], track['previewUrl']),
                  child: Card(
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        ListTile(
                          leading: track['imageUrl'] != null
                              ? Image.network(track['imageUrl'], width: 50, height: 50, fit: BoxFit.cover)
                              : Icon(Icons.music_note, size: 50),
                          title: Text(track['name']),
                          subtitle: Text(track['artist']),
                          trailing: Icon(Icons.play_arrow),
                        ),
                        
                        
                      ],
                    ),
                  ),
                );
              },
            )

          else
            Text('Search for songs to get started'),
          ],
        ),
      ),
    );
  }
  
}
  


class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, List<String>> _trackGenres = {};
  Map<String, Map<String, dynamic>> _trackMoods = {};
  Set<String> _selectedGenres = {};
  Set<String> _selectedMoods = {};

  bool _isSearching = false;
  String? _accessToken;
  DateTime? _tokenExpiry;

  @override
  void initState() {
    super.initState();
    _getAccessToken();
  }

  Future<void> _getAccessToken() async {
    try {
      final credentials = base64.encode(utf8.encode('$clientid:$secretClient'));
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _accessToken = data['access_token'];
          _tokenExpiry =
              DateTime.now().add(Duration(seconds: data['expires_in'] ?? 3600));
        });
      }
    } catch (e) {
      print('Error getting access token: $e');
    }
  }

  Future<void> _searchSongs(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() {
      _searchResults.clear();
      _trackGenres.clear();
      _trackMoods.clear();
      _selectedGenres.clear();
      _selectedMoods.clear();
      _isSearching = true;
    });

    try {
      if (_accessToken == null ||
          (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!))) {
        await _getAccessToken();
      }

      if (_accessToken == null) throw Exception('Failed to obtain token');

      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/search').replace(
          queryParameters: {'q': query, 'type': 'track', 'limit': '20'},
        ),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracks = data['tracks']['items'] as List;

        setState(() {
          _searchResults = tracks.map((track) {
            return {
              'name': track['name'] ?? 'Unknown',
              'artist': (track['artists'] as List?)?.isNotEmpty == true
                  ? track['artists'][0]['name'] ?? 'Unknown Artist'
                  : 'Unknown Artist',
              'artistId': (track['artists'] as List?)?.isNotEmpty == true
                  ? track['artists'][0]['id']
                  : null,
              'uri': track['uri'] ?? '',
              'id': track['id'],
              'previewUrl': track['preview_url'],
              'imageUrl': (track['album']['images'] as List?)?.isNotEmpty == true
                  ? track['album']['images'][0]['url']
                  : null,
            };
          }).toList();
        });

        // tracks with moods and genres
        await _enrichTracksWithMetadata();
      } else if (response.statusCode == 401) {
        await _getAccessToken();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Token refreshed - try searching again')),
        );
      }
    } catch (e) {
      print('Search error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error searching songs: $e')));
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _enrichTracksWithMetadata() async {
    if (_accessToken == null || _searchResults.isEmpty) return;

    try {
      // Fetch genres for each track
      for (var track in _searchResults) {
        if (track['artistId'] != null) {
          await _fetchArtistGenres(track['artistId'], track['id']);
        }
      }

      // Populate moods from genres
      _trackMoods.clear();
      for (var track in _searchResults) {
        final trackId = track['id'];
        if (trackId == null) continue;

        final genres = _trackGenres[trackId] ?? [];
        final moods = <String>{};

        for (var genre in genres) {
          genre = genre.toLowerCase();
          if (genre.contains('pop') || genre.contains('dance') || genre.contains('happy')) {
            moods.add('Happy');
          } else if (genre.contains('chill') || genre.contains('ambient') || genre.contains('soft')) {
            moods.add('Chill');
          } else if (genre.contains('rock') || genre.contains('metal') || genre.contains('intense')) {
            moods.add('Intense');
          } else if (genre.contains('sad') || genre.contains('blues') || genre.contains('emo')) {
            moods.add('Sad');
          } else {
            moods.add('Neutral');
          }
        }

        _trackMoods[trackId] = {'moods': moods.toList()};
      }

      print('Track moods populated from genres: ${_trackMoods.length}');
      setState(() {});
    } catch (e) {
      print('Error enriching tracks: $e');
    }
  }


  Future<void> _fetchAudioFeatures(List<String> trackIds) async {
    if (_accessToken == null || trackIds.isEmpty) return;

    try {
      // Spotify limits to 100 IDs per request
      for (var i = 0; i < trackIds.length; i += 100) {
        final batch = trackIds.sublist(
          i,
          (i + 100 > trackIds.length) ? trackIds.length : i + 100,
        );

        final response = await http.get(
          Uri.parse('https://api.spotify.com/v1/audio-features')
              .replace(queryParameters: {'ids': batch.join(',')}),
          headers: {'Authorization': 'Bearer $_accessToken'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final features = (data['audio_features'] as List?)
                  ?.where((f) => f != null && f['id'] != null)
                  .toList() ??
              [];

          for (var feature in features) {
            final trackId = feature['id'] as String;
            _trackMoods[trackId] = _analyzeMood(feature);
          }

          print('Batch moods populated: ${_trackMoods.length}');
        } else {
           print('Failed to fetch audio features: ${response.statusCode} ${response.body}');

        }
      }

      print('Total track moods: ${_trackMoods.length}');
    } catch (e) {
      print('Error fetching audio features: $e');
    }
  }



  Map<String, dynamic> _analyzeMood(Map<String, dynamic> features) {
    final valence = (features['valence'] ?? 0.5) as double;
    final energy = (features['energy'] ?? 0.5) as double;
    final danceability = (features['danceability'] ?? 0.5) as double;
    final acousticness = (features['acousticness'] ?? 0.5) as double;
    final tempo = (features['tempo'] ?? 120.0) as double;

    List<String> moods = [];

    if (valence >= 0.7 && energy >= 0.6) moods.add('Happy');
    if (valence >= 0.5 && energy < 0.4) moods.add('Chill');
    if (valence < 0.4 && energy >= 0.6) moods.add('Intense');
    if (valence < 0.4 && energy < 0.4) moods.add('Sad');

    if (danceability > 0.7) moods.add('Danceable');
    if (acousticness > 0.6) moods.add('Acoustic');
    if (tempo > 140) moods.add('Upbeat');
    if (energy > 0.8) moods.add('Powerful');

    if (moods.isEmpty) moods.add('Neutral');

    return {
      'moods': moods,
      'valence': valence,
      'energy': energy,
      'danceability': danceability,
    };
  }

  Future<void> _fetchArtistGenres(String artistId, String trackId) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/artists/$artistId'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final genres = (data['genres'] as List?)?.cast<String>() ?? [];
        _trackGenres[trackId] = genres;
      }
    } catch (e) {
      print('Error fetching artist genres: $e');
    }
  }

  Set<String> get _availableGenres {
    final genres = <String>{};
    for (var genreList in _trackGenres.values) {
      genres.addAll(genreList);
    }
    return genres;
  }

  Set<String> get _availableMoods {
    final moods = <String>{};
    for (var moodData in _trackMoods.values) {
      final trackMoods = moodData['moods'] as List<String>? ?? [];
      moods.addAll(trackMoods);
    }
    return moods;
  }

  List<Map<String, dynamic>> get _filteredResults {
    if (_selectedGenres.isEmpty && _selectedMoods.isEmpty) return _searchResults;

    return _searchResults.where((track) {
      final trackId = track['id'];
      if (trackId == null) return false;

      // genre filter
      if (_selectedGenres.isNotEmpty) {
        final genres = _trackGenres[trackId] ?? [];
        if (!genres.any((g) => _selectedGenres.contains(g))) return false;
      }

      // mood filter
      if (_selectedMoods.isNotEmpty) {
        final moods = _trackMoods[trackId]?['moods'] as List<String>? ?? [];
        if (!moods.any((m) => _selectedMoods.contains(m))) return false;
      }

      return true;
    }).toList();
  }

  Future<void> _addToQueue(Map<String, dynamic> track) async {
    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final trackId = track['id'];
      final genres = _trackGenres[trackId] ?? [];
      final moods = _trackMoods[trackId]?['moods'] as List<String>? ?? [];

      await FirebaseFirestore.instance
          .collection('lobbies')
          .doc(widget.roomId)
          .collection('queue')
          .add({
        'name': track['name'],
        'artist': track['artist'],
        'uri': track['uri'],
        'imageUrl': track['imageUrl'],
        'previewUrl': track['previewUrl'],
        'genres': genres,
        'moods': moods,
        'addedBy': userId,
        'timestamp': Timestamp.now(),
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Added "${track['name']}" to queue')));
    } catch (e) {
      print('Error adding to queue: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to add song to queue')));
    }
  }

  void _showSearchDialog() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color.fromARGB(255, 30, 30, 30),
            title: Text('Add Song to Queue'),
            content: Container(
              width: double.maxFinite,
              height: 500, // fixed height to prevent overflow
              child: SingleChildScrollView( 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search for a song...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (query) async {
                        await _searchSongs(query);
                        setDialogState(() {});
                      },
                    ),
                    SizedBox(height: 16),
                    
                    // Filter section
                    if (_searchResults.isNotEmpty) ...[
                      _buildFilterSection(setDialogState),
                      SizedBox(height: 16),
                    ],
                    
                    if (_isSearching)
                      CircularProgressIndicator()
                    else if (_filteredResults.isNotEmpty)
                      Container(
                        height: 300,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredResults.length,
                          itemBuilder: (context, index) {
                            final track = _filteredResults[index];
                            final trackId = track['id'];
                            final genres = _trackGenres[trackId] ?? [];
                            final moods = _trackMoods[trackId]?['moods'] as List<String>? ?? [];
                            
                            return Card(
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: track['imageUrl'] != null
                                        ? Image.network(track['imageUrl'], width: 50, height: 50, fit: BoxFit.cover)
                                        : Icon(Icons.music_note, size: 50),
                                    title: Text(track['name'], style: TextStyle(color: Colors.deepPurple)),
                                    subtitle: Text(track['artist'], style: TextStyle(color: Color.fromARGB(255, 131, 53, 233))),
                                    onTap: () async {
                                      await _addToQueue(track);
                                      Navigator.of(context).pop();
                                      setState(() {
                                        _searchResults = [];
                                        _trackGenres.clear();
                                        _trackMoods.clear();
                                        _selectedGenres.clear();
                                        _selectedMoods.clear();
                                        _searchController.clear();
                                      });
                                    },
                                  ),
                                  // Tags
                                  if (moods.isNotEmpty || genres.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          ...moods.take(2).map((mood) => Chip(
                                            label: Text(mood, style: TextStyle(fontSize: 10)),
                                            backgroundColor: Colors.deepPurple.withOpacity(0.3),
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                          )),
                                          ...genres.take(2).map((genre) => Chip(
                                            label: Text(genre, style: TextStyle(fontSize: 10)),
                                            backgroundColor: Colors.deepPurple.withOpacity(0.3),
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                          )),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    else if (_searchResults.isNotEmpty && _filteredResults.isEmpty)
                      Text('No songs match selected filters', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _searchResults = [];
                    _trackGenres.clear();
                    _trackMoods.clear();
                    _selectedGenres.clear();
                    _selectedMoods.clear();
                    _searchController.clear();
                  });
                },
                child: Text('Cancel'),
              ),
            ],
          );
        },
      );
    },
  );
}

  Widget _buildFilterSection(StateSetter setDialogState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Filter by Vibe', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            if (_selectedGenres.isNotEmpty || _selectedMoods.isNotEmpty)
              TextButton(
                onPressed: () {
                  setDialogState(() {
                    _selectedGenres.clear();
                    _selectedMoods.clear();
                  });
                },
                child: Text('Clear', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        SizedBox(height: 8),
        
        // Moods
        if (_availableMoods.isNotEmpty) ...[
          Text('Moods:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _availableMoods.take(6).map((mood) {
              final isSelected = _selectedMoods.contains(mood);
              return FilterChip(
                label: Text(mood, style: TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (selected) {
                  setDialogState(() {
                    if (selected) {
                      _selectedMoods.add(mood);
                    } else {
                      _selectedMoods.remove(mood);
                    }
                  });
                },
                selectedColor: Colors.deepPurple.withOpacity(0.4),
                checkmarkColor: Colors.white,
              );
            }).toList(),
          ),
          SizedBox(height: 8),
        ],
        
        // Genres
        if (_availableGenres.isNotEmpty) ...[
          Text('Genres:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _availableGenres.take(6).map((genre) {
              final isSelected = _selectedGenres.contains(genre);
              return FilterChip(
                label: Text(genre, style: TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (selected) {
                  setDialogState(() {
                    if (selected) {
                      _selectedGenres.add(genre);
                    } else {
                      _selectedGenres.remove(genre);
                    }
                  });
                },
                selectedColor: Colors.blue.withOpacity(0.4),
                checkmarkColor: Colors.white,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.all(10.0)),
            Text('Your Queue', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Padding(padding: const EdgeInsets.all(10.0)),
            FloatingActionButton(
              onPressed: () {
                _showSearchDialog();
              },
              child: Icon(Icons.add),
            ),
            SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('lobbies')
                  .doc(widget.roomId)
                  .collection('queue')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircularProgressIndicator();
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(25.0),
                    child: Text(''),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var queueDoc = snapshot.data!.docs[index];
                    Map<String, dynamic> song = queueDoc.data() as Map<String, dynamic>;
                    
                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: ListTile(
                        leading: song['imageUrl'] != null
                            ? Image.network(
                                song['imageUrl'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : Icon(Icons.music_note, size: 50),
                        title: Text(song['name'] ?? 'Unknown'),
                        subtitle: Text(song['artist'] ?? 'Unknown Artist'),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.deepPurple),
                          onPressed: () async {
                            await queueDoc.reference.delete();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Removed from queue')),
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
class ChatScreen extends StatefulWidget {

  final String roomId;

  const ChatScreen({super.key, required this.roomId,});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) {
      return;
    }

    try {
      String userId = _auth.currentUser!.uid;
      await FirebaseFirestore.instance.collection('lobbies').doc(widget.roomId).collection('messages').add({
        'message': _messageController.text.trim(),
        'userId': userId,
        'timestamp': Timestamp.now(),
      });
      
      _messageController.clear();
    } catch (e) {
      print('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message')),
      );
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();
    
    if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
      // Today - show time only
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      // Other days - show date and time
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('lobbies')
                  .doc(widget.roomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('No messages yet. Start the conversation!'));
                }

                return ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var messageDoc = snapshot.data!.docs[index];
                    Map<String, dynamic> message = messageDoc.data() as Map<String, dynamic>;
                    String messageText = message['message'] ?? '';
                    String userId = message['userId'] ?? '';
                    Timestamp timestamp = message['timestamp'] ?? Timestamp.now();
                    bool isCurrentUser = userId == _auth.currentUser?.uid;

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(userId)
                          .get(),
                      builder: (context, userSnapshot) {
                        String username = 'Unknown';
                        String? userImage;

                        if (userSnapshot.hasData && userSnapshot.data!.exists) {
                          var userData = userSnapshot.data!.data() as Map<String, dynamic>;
                          username = userData['displayname'] ?? 'Unknown';
                          userImage = userData['imageurl'];
                        }

                        return Align(
                          alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                            child: Column(
                              crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isCurrentUser) ...[
                                      userImage == null
                                          ? Icon(Icons.account_circle, size: 30)
                                          : ClipRRect(
                                              borderRadius: BorderRadius.circular(15.0),
                                              child: Builder(
                                                builder: (context) {
                                                  try {
                                                    return Image.memory(
                                                      base64Decode(userImage!),
                                                      height: 30,
                                                      width: 30,
                                                      fit: BoxFit.cover,
                                                    );
                                                  } catch (e) {
                                                    return Icon(Icons.account_circle, size: 30);
                                                  }
                                                },
                                              ),
                                            ),
                                      SizedBox(width: 8),
                                    ],
                                    Text(
                                      isCurrentUser ? 'You' : username,
                                      style: TextStyle(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.bold,
                                        color: isCurrentUser ? Colors.blue : Color.fromARGB(255, 131, 53, 233),
                                      ),
                                    ),
                                    if (isCurrentUser) ...[
                                      SizedBox(width: 8),
                                      userImage == null
                                          ? Icon(Icons.account_circle, size: 30)
                                          : ClipRRect(
                                              borderRadius: BorderRadius.circular(15.0),
                                              child: Builder(
                                                builder: (context) {
                                                  try {
                                                    return Image.memory(
                                                      base64Decode(userImage!),
                                                      height: 30,
                                                      width: 30,
                                                      fit: BoxFit.cover,
                                                    );
                                                  } catch (e) {
                                                    return Icon(Icons.account_circle, size: 30);
                                                  }
                                                },
                                              ),
                                            ),
                                    ],
                                  ],
                                ),
                                SizedBox(height: 4),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                  decoration: BoxDecoration(
                                    color: isCurrentUser ? const Color.fromARGB(255, 133, 39, 176) : const Color.fromARGB(255, 98, 39, 176),
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Text(
                                    messageText,
                                    style: TextStyle(fontSize: 16.0),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _formatTimestamp(timestamp),
                                  style: TextStyle(
                                    fontSize: 10.0,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 52, 52, 52),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.5),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                SizedBox(width: 8.0),
                CircleAvatar(
                  backgroundColor: const Color.fromARGB(255, 131, 53, 233),
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  }
}

class HistoryScreen extends StatefulWidget {
  final String roomId;
  
  const HistoryScreen({super.key, required this.roomId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  String? _playingUrl;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playPausePreview(String? previewUrl, String name) async {
    if (previewUrl == null || previewUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No preview available for $name')));
      return;
    }

    try {
      if (_playingUrl == previewUrl && _isPlaying) {
        await _audioPlayer.stop();
        setState(() {
          _playingUrl = null;
        });
        return;
      }

      if (_isPlaying) {
        await _audioPlayer.stop();
      }

      await _audioPlayer.play(UrlSource(previewUrl));
      setState(() {
        _playingUrl = previewUrl;
      });
    } catch (e) {
      print('Preview play error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not play preview: $e')));
    }
  }
  Future<void> _openInSpotify(String? uri, String name) async {
    if (uri != null && uri.isNotEmpty) {
      final Uri appUri = Uri.parse(uri);
      try {
        if (await canLaunchUrl(appUri)) {
          await launchUrl(appUri);
          return;
        }
      } catch (_) {}
      if (uri.startsWith('spotify:track:')) {
        final id = uri.split(':').last;
        final web = Uri.parse('https://open.spotify.com/track/$id');
        if (await canLaunchUrl(web)) {
          await launchUrl(web, mode: LaunchMode.externalApplication);
          return;
        }
      } else if (uri.contains('open.spotify.com')) {
        final web = Uri.parse(uri);
        if (await canLaunchUrl(web)) {
          await launchUrl(web, mode: LaunchMode.externalApplication);
          return;
        }
      }
    }
    final spotifyHome = Uri.parse('spotify:');
    if (await canLaunchUrl(spotifyHome)) {
      await launchUrl(spotifyHome);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open Spotify for $name')));
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Your Past Songs',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('lobbies')
                  .doc(widget.roomId)
                  .collection('history')
                  .orderBy('playedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircularProgressIndicator();
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No songs played yet'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var historyDoc = snapshot.data!.docs[index];
                    Map<String, dynamic> song = historyDoc.data() as Map<String, dynamic>;
                    Timestamp playedAt = song['playedAt'] ?? Timestamp.now();
                    
                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: ListTile(
                        leading: song['imageUrl'] != null
                            ? Image.network(
                                song['imageUrl'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : Icon(Icons.music_note, size: 50),
                        title: Text(song['name'] ?? 'Unknown'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(song['artist'] ?? 'Unknown Artist'),
                            SizedBox(height: 4),
                            Text(
                              _formatTimestamp(playedAt),
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: (song['preview_url'] ?? song['previewUrl']) != null
                            ? IconButton(
                                icon: Icon(
                                  (_isPlaying && _playingUrl == (song['preview_url'] ?? song['previewUrl'])) ? Icons.pause : Icons.play_arrow,
                                ),
                                onPressed: () => _playPausePreview(song['preview_url'] ?? song['previewUrl'], song['name'] ?? 'Unknown'),
                              )
                            : IconButton(
                                icon: Icon(Icons.open_in_new),
                                onPressed: () => _openInSpotify(song['uri'] ?? song['spotify_uri'] ?? song['spotifyUri'], song['name'] ?? 'Unknown'),
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();
    
    if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
      return 'Today at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.month}/${dateTime.day} at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  void showVotingDialog() {
    final votesRef = FirebaseFirestore.instance
        .collection('lobbies')
        .doc(widget.roomId)
        .collection('votes');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 30, 30, 30),
          title: Text('Voting', style: TextStyle(color: Colors.white)),
          content: FutureBuilder<List<DocumentSnapshot>>(
            future: Future.wait([
              votesRef.doc('song1').get(),
              votesRef.doc('song2').get(),
              votesRef.doc('song3').get(),
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null || data['name'] == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey[800],
                            child: Icon(Icons.music_note, color: Colors.white, size: 40),
                          ),
                          SizedBox(height: 8),
                          Text('No Song', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: data['name'] == null ? null : () async {
                            // Atomically increment vote count in Firestore
                            await votesRef.doc('song${i + 1}').update({
                              'votenum': FieldValue.increment(1),
                            });
                            Navigator.of(context).pop();
                          },
                          child: data['imageUrl'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    data['imageUrl'],
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.grey[800],
                                  child: Icon(Icons.music_note, color: Colors.white, size: 40),
                                ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          data['name'] ?? '',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          data['artist'] ?? '',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text('Votes: ${data['votenum'] ?? 0}', style: TextStyle(color: Colors.deepPurpleAccent)),
                      ],
                    ),
                  );
                }),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('No vote', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}