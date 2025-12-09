import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'drawer.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/spotify_web_playback_service.dart';

String clientid = "eecdb44badc44526a3fdf6bfe3b8308b";
String secretClient = "977979869e7a48d9bbc8e1478c953ae3";


class Partyscreen extends StatefulWidget {
  const Partyscreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<Partyscreen> createState() => _PartyScreen();
}

class _PartyScreen extends State<Partyscreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
          SongScreen(),
          QueueScreen(roomId: widget.roomId),
          ChatScreen(roomId: widget.roomId),
          HistoryScreen(),
        ]
      ),
    );
  }
}

class SongScreen extends StatefulWidget {
  const SongScreen({super.key});

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
              'uri': track['uri'] ?? '',
              'previewUrl': track['preview_url'],
              'imageUrl': (track['album']['images'] as List?)?.isNotEmpty == true
                  ? track['album']['images'][0]['url']
                  : null,
            };
          }).toList();
        });

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
            // Search results
            if (_isSearching)
              CircularProgressIndicator()
            else if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
              Text('No songs found')
            else if (_searchResults.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final track = _searchResults[index];
                  return GestureDetector(
                    onTap: () => _playSong(track['uri'], track['name'], track['previewUrl']),
                    child: Card(
                      margin: EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: track['imageUrl'] != null
                            ? Image.network(
                                track['imageUrl'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : Icon(Icons.music_note, size: 50),
                        title: Text(track['name']),
                        subtitle: Text(track['artist']),
                        trailing: Icon(Icons.play_arrow),
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
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center (
        child: Column(
          children: [
            Text('Current Queue'),
            FloatingActionButton(
              onPressed: () {
                // Add song to queue
              },
              child: Icon(Icons.add),
            ),
          ],
      )
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
                                        color: Colors.grey[700],
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
                                    color: isCurrentUser ? Colors.blue[100] : Colors.grey[300],
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
              color: Colors.white,
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
                  backgroundColor: Theme.of(context).primaryColor,
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
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center (
        child: Column(
          children: [
            Text('Your Past Songs'),
          ],
      )
    ),
    );
  }
}