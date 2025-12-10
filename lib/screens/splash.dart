import 'package:flutter/material.dart';
import 'Signin.dart';
import 'Signup.dart';

class Splash extends StatefulWidget {
  const Splash({super.key, required this.title});

  final String title;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 98, 39, 176),
        title: Text(widget.title, style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Welcome to Vibcheckz', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            Text('A collaborative music experience', style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic)),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Icon(Icons.equalizer, size: 100, color: Colors.green),
            Icon(Icons.music_note, size: 100, color: Color.fromARGB(255, 98, 39, 176),),
            Icon(Icons.graphic_eq, size: 100, color: Colors.green),
              ],
            ),
            SizedBox(height: 20),
            Text('Join in on the good vibes!', style: TextStyle(fontSize: 18)),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Signin(title: 'Sign In'),
                  ),
                );
              },
              child: Text('Sign In'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => Signup()),
                );
              },
              child: Text('Sign Up'),
            ),
            SizedBox(height: 40),
            Text('An experience powered by Spotify', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.green)),
          ],
        ),
      ),
    );
  }
}