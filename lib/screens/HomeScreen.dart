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
    _tabController = TabController(length: 2, vsync: this);
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
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          GroupListScreen(),
          PartyListScreen(),
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
            title: Text('Create a Room'),
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
                
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: 'Visibility'),
                  items: <String>['public', 'private'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    visibility = newValue!;
                  },
                ),
                CheckboxListTile(
                  title: Text('Enable Voting'),
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
            Text('Connect With Friends'),
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => Partyscreen(roomId: code.toUpperCase())),
                  );
                }
              },
              child: Text('Join a Party'),
            ),
            Text('OR'),
            ElevatedButton(
              onPressed: () {
                showRoomDialogue(context);
              },
              child: Text('Host a Party'),
            ),
            Text('Or Make Some New Ones'),
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
                    return ListTile(
                      title: Text(lobby['lobbyName'] ?? 'No Name'),
                      subtitle: Text('Visibility: ${lobby['visibility']}'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => Partyscreen(roomId: lobby.id)),
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
            Text('Your Past Parties'),
          ],
      )
    ),
    );
  }
}

void hostParty() {

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
      'currentSong': null, //to be used later maybe?
    });

    await docRef.collection('messages').add({
      'test': 'test',
    });

    await docRef.collection('history').add({
      'test': 'test',
    });

    return lobbyCode;
  } catch (e) {
    print("Error creating lobby: $e");
    return null;
  }
}

