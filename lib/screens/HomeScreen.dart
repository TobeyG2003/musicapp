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
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center (
        child: Column(
          children: [
            Text('Your Song History'),
          ],
      )
    ),
    );
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