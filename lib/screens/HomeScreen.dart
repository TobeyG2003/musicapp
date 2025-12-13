import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'drawer.dart';
import 'dart:math';
import 'PartyScreen.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.title});

  final String title;

  @override
  State<HomeScreen> createState() => _HomeScreen();
}

class _HomeScreen extends State<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 98, 39, 176),
        title: Text(widget.title, style: TextStyle(color: Colors.white,)),
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
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Parties'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Your History'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          GroupListScreen(),
          PartyListScreen(),
          SongHistoryScreen(),
        ]
      ),
    );
  }
}

 Future<void> showRoomDialogue(BuildContext context) async {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _roomNameController = TextEditingController();
  final username;

  String? userId = _auth.currentUser?.uid;
      if (userId != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (userDoc.exists) {
          username = userDoc['displayname'];
        } else {
          username = 'Unknown';
        }

  final String roomName = '';
  bool isVoting = true;
  String visibility = 'public';
    _roomNameController.text = '$username\'s Room';

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return AlertDialog(
            backgroundColor: const Color.fromARGB(255, 39, 39, 39),
            title: Text('Create a Room', style: TextStyle(color: Colors.white),),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _roomNameController,
                    decoration: InputDecoration(labelText: 'Room Name'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a room name';
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  dropdownColor: const Color.fromARGB(255, 39, 39, 39),
                  decoration: InputDecoration(labelText: 'Visibility',),
                  items: <String>['public', 'private'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value, style: TextStyle(color: Colors.white),)
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    visibility = newValue!;
                  },
                ),
                CheckboxListTile(
                  title: Text('Enable Voting', style: TextStyle(color: Colors.white),),
                  value: isVoting,
                  onChanged: (bool? value) {
                    setState(() {
                      isVoting = value!;
                    });
                  },
                ),
              ],
            ),
            actions: <Widget>[
              ElevatedButton(
                child: Text('Cancel'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              ElevatedButton(
                child: Text('Create'),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    String? lobbyCode = await createLobby(visibility, isVoting, _roomNameController.text);
                    Navigator.of(context).pop();
                     Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Partyscreen(roomId: lobbyCode!)),
                    );
                  }
                },
              ),
            ],
          );
        },
      );
    },
  );
}
}

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center (
        child: Column(
          children: [
            SizedBox(height: 20),
            Text('Connect With Friends', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),),
            SizedBox(height: 10),
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _codeController,
                decoration: InputDecoration(labelText: 'Enter Room Code'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a room code';
                  }
                  return null;
                },
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final code = _codeController.text.trim();
                  final docRef = FirebaseFirestore.instance.collection('lobbies').doc(code.toUpperCase());
                  final docSnapshot = await docRef.get();
                  if (!docSnapshot.exists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Room code does not exist')),
                    );
                    return;
                  }
                  await joinPartyForCurrentUser(code.toUpperCase());
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Partyscreen(roomId: code.toUpperCase())),
                  );
                }
              },
              child: Text('Join a Party'),
            ),
            Text('- OR -'),
            ElevatedButton(
              onPressed: () {
                showRoomDialogue(context);
              },
              child: Text('Host a Party'),
            ),
            SizedBox(height: 20),
            Text('Or Make Some New Ones', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),),
            StreamBuilder(
              stream: FirebaseFirestore.instance.collection('lobbies').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return CircularProgressIndicator();
                }
                final lobbies = snapshot.data!.docs;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: lobbies.length,
                  itemBuilder: (context, index) {
                    final lobby = lobbies[index];
                    if (lobby['visibility'] != 'public') {
                      return SizedBox.shrink();
                    }
                    return lobbycard(lobby: {
                      'id': lobby.id,
                      'lobbyName': lobby['lobbyName'],
                      'visibility': lobby['visibility'],
                      'voting': lobby['voting'],
                    });
                  },
                );
              },
            ),
          ],
      )
    ),
    );
  }
}

class PartyListScreen extends StatefulWidget {
  const PartyListScreen({super.key});

  @override
  State<PartyListScreen> createState() => _PartyListScreenState();
}

class _PartyListScreenState extends State<PartyListScreen> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center (
        child: Column(
          children: [
            SizedBox(height: 20),
            Text('Your Past Parties', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),),
            StreamBuilder(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_auth.currentUser?.uid)
                  .collection('parties')
                  .orderBy('joinedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return CircularProgressIndicator();
                }
                final parties = snapshot.data!.docs;
                // Filter out sample documents (id 'test' or 'sample')
                final realParties = parties.where((p) => p.id != 'test' && p.id != 'sample').toList();
                if (realParties.isEmpty) {
                  return Text('You have not joined any parties yet.');
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: realParties.length,
                  itemBuilder: (context, index) {
                    final party = realParties[index];
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('lobbies')
                          .doc(party.id)
                          .get(),
                      builder: (context, lobbySnapshot) {
                        if (!lobbySnapshot.hasData) {
                          return SizedBox.shrink();
                        }
                        if (!lobbySnapshot.data!.exists) {
                          return SizedBox.shrink();
                        }
                        final lobbyData = lobbySnapshot.data!;
                        return lobbycard(
                          lobby: {
                            'id': party.id,
                            'lobbyName': lobbyData['lobbyName'],
                            'visibility': lobbyData['visibility'],
                            'voting': lobbyData['voting'],
                          },
                          onDelete: () async {
                            final String? uid = _auth.currentUser?.uid;
                            if (uid == null) return;
                            try {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('parties')
                                  .doc(party.id)
                                  .delete();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Removed from history')),
                              );
                            } catch (e) {
                              print('Error removing party from history: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to remove from history')),
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
      )
    ),
    );
  }
}
class SongHistoryScreen extends StatefulWidget {
  const SongHistoryScreen({super.key});

  @override
  State<SongHistoryScreen> createState() => _SongHistoryScreenState();
}
class _SongHistoryScreenState extends State<SongHistoryScreen> {
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
    // Try open Spotify app first, then fallback to web player
    if (uri != null && uri.isNotEmpty) {
      // If URI is a spotify: URI use that, otherwise try to extract id for web URL
      final Uri appUri = Uri.parse(uri);
      try {
        if (await canLaunchUrl(appUri)) {
          await launchUrl(appUri);
          return;
        }
      } catch (_) {}
      // If uri isn't an app URI, try to convert to https open.spotify.com
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

    // As a last resort, open Spotify home
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
                  .collection('users')
                  .doc(_auth.currentUser?.uid)
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
}

String generateRandomCode() {
  const String alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  Random random = Random();
  String code = "";
  for (int i = 0; i < 6; i++) {
    code += alpha[random.nextInt(alpha.length)];
  }
  return code;
}

Future<String?> createLobby(String visibility, bool voting, String lobbyName) async {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String lobbyCode = generateRandomCode();
  final DocumentReference docRef = _firestore.collection('lobbies').doc(lobbyCode);
  final DocumentSnapshot docSnap = await docRef.get();

  if (docSnap.exists) {
    return createLobby(visibility, voting, lobbyName);
  }

  try {
    await docRef.set({
      'visibility': visibility,
      'lobbyName': lobbyName,
      'createdAt': FieldValue.serverTimestamp(),
      'voting': voting,
      'currentSong': null,
    });

    await docRef.collection('messages').add({
      'test': 'test',
    });

    await docRef.collection('history').add({
      'test': 'test',
    });

    await docRef.collection('queue').add({
      'test': 'test',
    });

    joinPartyForCurrentUser(lobbyCode);
    return lobbyCode;
  } catch (e) {
    print("Error creating lobby: $e");
    return null;
  }
}

class lobbycard extends StatefulWidget {
  const lobbycard({
    super.key,
    required this.lobby,
    this.onDelete,
  });

  final Map<String, dynamic> lobby;
  final VoidCallback? onDelete;

  @override
  State<lobbycard> createState() => _lobbycardState();
}

class _lobbycardState extends State<lobbycard> {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await joinPartyForCurrentUser(widget.lobby['id']);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => Partyscreen(roomId: widget.lobby['id'])),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Color.fromARGB(255, 131, 53, 233)),
          borderRadius: BorderRadius.circular(8),
        ),
      margin: EdgeInsets.all(8),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.lobby['lobbyName'] ?? 'No Name',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 131, 53, 233)),
                ),
              ),
              if (widget.onDelete != null)
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: widget.onDelete,
                ),
            ],
          ),
          SizedBox(height: 8),
          Text('Visibility: ${widget.lobby['visibility']}'),
          Text('Voting: ${widget.lobby['voting'] ? "Enabled" : "Disabled"}'),
        ],
      ),
    ),
    );
  }
}

Future<void> joinPartyForCurrentUser(String lobbyId) async {
  final String? uid = _auth.currentUser?.uid;
  if (uid == null) return;

  final userPartyRef = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('parties')
      .doc(lobbyId);

  final userPartySnapshot = await userPartyRef.get();
  if (!userPartySnapshot.exists) {
    await userPartyRef.set({
      'joinedAt': FieldValue.serverTimestamp(),
    });
  } else {
    await userPartyRef.update({
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }
}