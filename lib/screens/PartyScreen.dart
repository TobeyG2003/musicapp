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
    _tabController = TabController(length: 3, vsync: this);
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
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SongScreen(),
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
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center (
        child: Column(
          children: [
            Text('Current Song'),
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