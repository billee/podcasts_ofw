// lib/core/auth/auth_service.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _adminUser;
  bool _isAdmin = false;

  User? get adminUser => _adminUser;
  bool get isAdminLoggedIn => _adminUser != null && _isAdmin;

  AuthService() {
    // Listen to auth state changes
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  void _onAuthStateChanged(User? user) async {
    _adminUser = user;

    if (user != null) {
      // Check if user is admin
      final userDoc = await _firestore.collection('admins').doc(user.uid).get();
      _isAdmin = userDoc.exists;
    } else {
      _isAdmin = false;
    }

    notifyListeners();
  }

  Future<bool> loginAdmin(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Verify admin role in Firestore
      final userDoc = await _firestore
          .collection('admins')
          .doc(userCredential.user!.uid)
          .get();

      if (userDoc.exists) {
        return true;
      } else {
        await _auth.signOut();
        return false;
      }
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }
}
