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

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center (
        child: Column(
          children: [
            Text('Connect With Friends'),
            ElevatedButton(
              onPressed: () {
                
              },
              child: Text('Join a Party'),
            ),
            ElevatedButton(
              onPressed: () {
                createLobby('public', true, 'testlobby');
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