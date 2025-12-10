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
import 'HomeScreen.dart';

class appbarDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color.fromARGB(255, 98, 39, 176),
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(child: Text('Navigation', style: TextStyle(color: Colors.white, fontSize: 42)), 
            decoration: BoxDecoration(color: Color.fromARGB(255, 98, 39, 176)),),
            ListTile(
              title: const Text('Group List', style: TextStyle(color: Colors.white, fontSize: 25)),
              trailing: Icon(Icons.group, color: Colors.white,),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => HomeScreen(title: 'Home')),
                );
              },
            ),
            ListTile(
              title: const Text('My Profile', style: TextStyle(color: Colors.white, fontSize: 25)),
              trailing: Icon(Icons.account_circle, color: Colors.white,),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => profilescreen()),
                );
              },
            ),
            ListTile(
              title: const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 25)),
              trailing: Icon(Icons.settings, color: Colors.white,),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => settingsscreen()),
                );
              },
            ),
          ],
        ),
    );
  }
}

class profilescreen extends StatefulWidget {
  @override
  _profilescreenState createState() => _profilescreenState();
}

class _profilescreenState extends State<profilescreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  bool _isLoadingData = true;
  String? name;
  String? currentimage;
  String? imagestring;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      String? userId = _auth.currentUser?.uid;
      if (userId != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();

        if (userDoc.exists) {
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;
          setState(() {
            name = userData['displayname'];
            currentimage = userData['imageurl'];
            _isLoadingData = false;
          });
        } else {
          setState(() {
            _isLoadingData = false;
          });
        }
      } else {
        setState(() {
          _isLoadingData = false;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  Future<void> _updateDisplayName() async {
    if (_displayNameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please enter a display name')));
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      String userId = _auth.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'displayname': _displayNameController.text,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Display name updated successfully')),
      );
      setState(() {
        name = _displayNameController.text;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating display name: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProfileImage() async {
    if (imagestring == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please select an image first')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String userId = _auth.currentUser!.uid;
      String cleanBase64 = imagestring!.replaceAll(RegExp(r'\s+'), '');

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'imageurl': cleanBase64,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile image updated successfully')),
      );
      setState(() {
        currentimage = cleanBase64;
      });
    } catch (e) {
      print('Error updating profile image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile image: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(title: Text('Profile Screen', style: TextStyle(color: Colors.white)), backgroundColor: const Color.fromARGB(255, 98, 39, 176),),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Profile Screen', style: TextStyle(color: Colors.white)), backgroundColor: const Color.fromARGB(255, 98, 39, 176),),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            currentimage == null
                ? Icon(Icons.account_circle, size: 225)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(100.0),
                    child: Builder(
                      builder: (context) {
                        try {
                          return Image.memory(
                            base64Decode(currentimage!),
                            height: 200,
                            width: 200,
                            fit: BoxFit.cover,
                          );
                        } catch (e) {
                          return Icon(Icons.account_circle, size: 225);
                        }
                      },
                    ),
                  ),
            SizedBox(height: 10),
            Text(
              name ?? 'No name set',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text('Display Name'),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: 'New Display Name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : _updateDisplayName,
              child: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Update Display Name'),
            ),
            SizedBox(height: 20),
            Text('Profile Picture'),
            ElevatedButton(
              onPressed: () async {
                final ImagePicker picker = ImagePicker();
                final XFile? image = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (image != null) {
                  final Uint8List bytes = await image.readAsBytes();
                  setState(() {
                    imagestring = base64Encode(bytes);
                  });
                  print('Selected image path: ${image.path}');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 188, 44, 44),
              ),
              child: Text(
                'Select Image',
                style: TextStyle(color: Colors.white),
              ),
            ),
            if (imagestring != null) ...[
              SizedBox(height: 10),
              Text('Image selected', style: TextStyle(fontSize: 16)),
              SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(100.0),
                child: Builder(
                  builder: (context) {
                    try {
                      return Image.memory(
                        base64Decode(imagestring!),
                        height: 200,
                        width: 200,
                        fit: BoxFit.cover,
                      );
                    } catch (e) {
                      return Container(
                        height: 150,
                        width: 200,
                        color: Colors.grey[300],
                        child: Center(child: Text('Error loading image')),
                      );
                    }
                  },
                ),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: _isLoading ? null : _updateProfileImage,
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Save Profile Image'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class settingsscreen extends StatefulWidget {
  @override
  _settingsscreenState createState() => _settingsscreenState();
}

class _settingsscreenState extends State<settingsscreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final GlobalKey<FormState> _nameKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _emailKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _passKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _currentPassKey = GlobalKey<FormState>();
  TextEditingController _passController = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  TextEditingController _currentPassController = TextEditingController();
  TextEditingController _firstNameController = TextEditingController();
  TextEditingController _lastNameController = TextEditingController();
  String? currentfname;
  String? currentlname;

  void initState() {
    super.initState();
    String userId = _auth.currentUser!.uid;
    FirebaseFirestore.instance.collection('users').doc(userId).get().then((
      doc,
    ) {
      if (doc.exists) {
        setState(() {
          currentfname = doc['firstname'];
          currentlname = doc['lastname'];
        });
      }
    });
  }

  void _signOut() async {
    await _auth.signOut();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Signed out successfully')));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void updatename() async {
    try {
      String userId = _auth.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'firstname': _firstNameController.text,
        'lastname': _lastNameController.text,
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Name updated successfully')));
      setState(() {
        currentfname = _firstNameController.text;
        currentlname = _lastNameController.text;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update name: $e')));
    }
  }

  void updatepassword() async {
    try {
      if (_auth.currentUser != null && _auth.currentUser?.email != null) {
        AuthCredential credential = EmailAuthProvider.credential(
          email: _auth.currentUser!.email!,
          password: _currentPassController.text,
        );
        await _auth.currentUser!.reauthenticateWithCredential(credential);
      }
      await _auth.currentUser?.updatePassword(_passController.text);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password updated successfully')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update password: $e')));
    }
  }

  void updateemail() async {
    try {
      if (_auth.currentUser != null && _auth.currentUser?.email != null) {
        AuthCredential credential = EmailAuthProvider.credential(
          email: _auth.currentUser!.email!,
          password: _currentPassController.text,
        );
        await _auth.currentUser!.reauthenticateWithCredential(credential);
      }
      await _auth.currentUser?.updateEmail(_emailController.text);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Email updated successfully')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update email: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings Screen', style: TextStyle(color: Colors.white)), backgroundColor: const Color.fromARGB(255, 98, 39, 176),),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Name'),
            Text('$currentfname $currentlname'),
            ElevatedButton(onPressed: _signOut, child: Text('Sign Out')),
            SizedBox(height: 20),
            Text('Update Personal Information'),
            SizedBox(height: 10),
            Form(
              key: _nameKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      labelText: 'New First Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Please enter your First Name';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 10),
                  TextFormField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      labelText: 'New Last Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Please enter your Last Name';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 15),
                  ElevatedButton(
                    onPressed: () {
                      if (_nameKey.currentState!.validate()) {
                        updatename();
                      }
                    },
                    child: Text('Update First & Last Name'),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10),
            Text('Update Credentials (Current Password Required)'),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Form(
                    key: _currentPassKey,
                    child: TextFormField(
                      controller: _currentPassController,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return 'Please enter your current password';
                        }
                        return null;
                      },
                      obscureText: true,
                    ),
                  ),
                  SizedBox(height: 15),
                  Form(
                    key: _passKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _passController,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
                              return 'Please enter your new password';
                            }
                            return null;
                          },
                          obscureText: true,
                        ),
                        SizedBox(height: 5),
                        ElevatedButton(
                          onPressed: () {
                            bool currentPassValid =
                                _currentPassKey.currentState?.validate() ??
                                false;
                            bool newPassValid =
                                _passKey.currentState?.validate() ?? false;
                            if (currentPassValid && newPassValid) {
                              updatepassword();
                            }
                          },
                          child: Text('Update Password'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  Form(
                    key: _emailKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'New Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
                              return 'Please enter your new email';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () {
                            bool currentPassValid =
                                _currentPassKey.currentState?.validate() ??
                                false;
                            bool newEmailValid =
                                _emailKey.currentState?.validate() ?? false;
                            if (currentPassValid && newEmailValid) {
                              updateemail();
                            }
                          },
                          child: Text('Update Email'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}