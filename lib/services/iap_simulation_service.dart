import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/app_models.dart';
import '../app/global_context.dart';

class IAPSimulationService with ChangeNotifier {
  // Storage keys
  final String _trialStartKey = 'trial_start_date';
  final String _purchasedKey = 'has_purchased';
  final String _userIdKey = 'user_id';

  // State
  int daysRemaining = 0;
  bool _isLoading = true;
  String? _userId;

  // Firestore collection in admin project
  final String _usersCollection = 'users';

  IAPSimulationService() {
    _initialize();
  }

  // Initialize the black box
  Future<void> _initialize() async {
    await _initializeUser();
    await _initializeTrial();
    _isLoading = false;
    notifyListeners();
  }

  // User management
  Future<void> _initializeUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString(_userIdKey);

    if (_userId == null) {
      _userId = _generateUserId();
      await prefs.setString(_userIdKey, _userId!);
      print('🆕 New user created: $_userId');

      // Create user document in admin project with retry
      bool success = false;
      int retries = 3;

      while (!success && retries > 0) {
        try {
          await _createUserInAdminProject();
          success = true;
        } catch (e) {
          retries--;
          print(
              '❌ Failed to create user document. Retries left: $retries. Error: $e');
          if (retries > 0) {
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }
    } else {
      print('👤 Existing user: $_userId');
      // Update last active timestamp
      await _updateUserLastActive();
    }
  }

  Future<void> _updateUserLastActive() async {
    if (_userId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(_userId)
          .set({
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('✅ User last active updated: $_userId');
    } catch (e) {
      print('❌ Error updating user last active: $e');
      // If updating fails, try to create the user document
      await _createUserInAdminProject();
    }
  }

  String _generateUserId() {
    final random = Random();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return 'user_${DateTime.now().millisecondsSinceEpoch}_${String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(random.nextInt(chars.length))))}';
  }

  // Store user data in admin project Firestore
  Future<void> _createUserInAdminProject() async {
    try {
      final userData = {
        'userId': _userId,
        'createdAt': FieldValue.serverTimestamp(),
        'trialStartDate': FieldValue.serverTimestamp(),
        'isSubscribed': false,
        'lastActive': FieldValue.serverTimestamp(),
        'appVersion': '1.0.0',
        'platform': 'mobile',
        'status': 'active',
        'createdVia': 'mobile_app',
      };

      print('🔄 Creating user in admin database: $_userId');

      await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(_userId)
          .set(userData);

      print('✅ SUCCESS: User document created in admin project');
      print('📊 User ID: $_userId');
      print('💾 Collection: $_usersCollection');
    } catch (e) {
      print('❌ ERROR creating user document in admin project: $e');

      if (e is FirebaseException) {
        print('❌ Firebase error code: ${e.code}');
        print('❌ Firebase error message: ${e.message}');
      }

      // Try one more time with a simple document
      try {
        print('🔄 Retrying with simple document...');
        await FirebaseFirestore.instance
            .collection(_usersCollection)
            .doc(_userId)
            .set({
          'userId': _userId,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'active',
        });
        print('✅ SUCCESS: Simple user document created');
      } catch (retryError) {
        print(
            '❌ FAILED: Could not create user document even with retry: $retryError');
      }
    }
  }

  // Trial management
  Future<void> _initializeTrial() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(_trialStartKey)) {
      await prefs.setString(_trialStartKey, DateTime.now().toIso8601String());
      print('Trial started: ${DateTime.now()}');
    }

    await _calculateTrialDays();
  }

  Future<void> _calculateTrialDays() async {
    final prefs = await SharedPreferences.getInstance();
    final trialStartString = prefs.getString(_trialStartKey);

    if (trialStartString != null) {
      final trialStart = DateTime.parse(trialStartString);
      final trialEnd = trialStart.add(Duration(days: 7));
      final now = DateTime.now();

      // Calculate remaining days, but show at least 1 if we're still in trial
      final totalDaysRemaining = trialEnd.difference(now).inDays;

      if (totalDaysRemaining < 0) {
        daysRemaining = 0;
      } else {
        // If we have any time left in the trial (even partial day), show at least 1 day
        daysRemaining = totalDaysRemaining == 0 && now.isBefore(trialEnd)
            ? 1
            : totalDaysRemaining;
      }

      print('Trial days remaining: $daysRemaining');
      print('Trial start: $trialStart');
      print('Trial end: $trialEnd');
      print('Now: $now');
    }
  }

  // Black Box IAP Simulation
  Future<void> simulatePurchase() async {
    print('🚀 IAP BLACK BOX: Starting purchase simulation...');

    // Step 1: Show processing UI
    if (GlobalContext.context.mounted) {
      ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
        SnackBar(
          content: Text('Processing purchase...'),
          backgroundColor: Colors.blue,
        ),
      );
    }

    // Step 2: Simulate network delay
    await Future.delayed(Duration(seconds: 2));

    // Step 3: Process payment (simulated)
    print('💳 IAP BLACK BOX: Processing payment...');
    await Future.delayed(Duration(seconds: 1));

    // Step 4: Verify payment (simulated - always successful)
    print('✅ IAP BLACK BOX: Payment verified successfully');

    // Step 5: Activate subscription
    await _activateSubscription();

    // Step 6: Show success
    if (GlobalContext.context.mounted) {
      ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
        SnackBar(
          content: Text('🎉 Subscription activated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }

    print('🏁 IAP BLACK BOX: Purchase simulation completed');
  }

  Future<void> _activateSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_purchasedKey, true);

    // Update admin project
    await _updateSubscriptionStatus(true);

    print('Subscription activated for user: $_userId');
    notifyListeners();
  }

  Future<void> _updateSubscriptionStatus(bool isSubscribed) async {
    if (_userId == null) {
      print('❌ Cannot update subscription: user ID is null');
      return;
    }

    try {
      final updateData = {
        'isSubscribed': isSubscribed,
        'subscriptionActivatedAt':
            isSubscribed ? FieldValue.serverTimestamp() : null,
        'lastActive': FieldValue.serverTimestamp(),
        'subscriptionStatus': isSubscribed ? 'active' : 'inactive',
      };

      // Use set with merge: true to create the document if it doesn't exist
      await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(_userId)
          .set(updateData, SetOptions(merge: true));

      print('✅ Subscription status updated in admin project: $isSubscribed');
      print('✅ Update data: $updateData');
    } catch (e) {
      print('❌ Error updating subscription status: $e');
      if (e is FirebaseException) {
        print('❌ Firebase error code: ${e.code}');
        print('❌ Firebase error message: ${e.message}');
      }

      // Try to create the user document if it doesn't exist
      await _createUserInAdminProject();
      // Then try updating again
      await _updateSubscriptionStatus(isSubscribed);
    }
  }

  // Restore purchases simulation
  Future<void> simulateRestorePurchases() async {
    print('🔄 IAP BLACK BOX: Starting restore simulation...');

    if (GlobalContext.context.mounted) {
      ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
        SnackBar(
          content: Text('Checking for previous purchases...'),
          backgroundColor: Colors.blue,
        ),
      );
    }

    // Simulate network delay
    await Future.delayed(Duration(seconds: 2));

    try {
      if (_userId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection(_usersCollection)
            .doc(_userId)
            .get();

        if (userDoc.exists && userDoc.data()!['isSubscribed'] == true) {
          // User has active subscription in admin project
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_purchasedKey, true);

          if (GlobalContext.context.mounted) {
            ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
              SnackBar(
                content: Text('✅ Purchase restored successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          notifyListeners();
        } else {
          if (GlobalContext.context.mounted) {
            ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
              SnackBar(
                content: Text('No previous purchase found.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error restoring purchases: $e');
      if (GlobalContext.context.mounted) {
        ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
          SnackBar(
            content: Text('Error restoring purchases. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Access state check
  Future<AppAccessState> getAccessState() async {
    final prefs = await SharedPreferences.getInstance();

    // Check local subscription status first
    final hasPurchased = prefs.getBool(_purchasedKey) ?? false;
    if (hasPurchased) {
      return AppAccessState.hasAccess;
    }

    // Fallback: Check admin project for subscription status
    try {
      if (_userId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection(_usersCollection)
            .doc(_userId)
            .get();

        if (userDoc.exists && userDoc.data()!['isSubscribed'] == true) {
          await prefs.setBool(_purchasedKey, true);
          return AppAccessState.hasAccess;
        }
      }
    } catch (e) {
      print('Error checking admin project: $e');
    }

    // Check trial status
    final trialStartString = prefs.getString(_trialStartKey);
    if (trialStartString != null) {
      final trialStart = DateTime.parse(trialStartString);
      final trialEnd = trialStart.add(Duration(days: 7));
      final now = DateTime.now();

      if (now.isBefore(trialEnd)) {
        await _calculateTrialDays();
        return AppAccessState.inTrial;
      }
    }

    return AppAccessState.trialExpired;
  }

  // Debug methods
  Future<void> debugPrintState() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    print('=== IAP BLACK BOX DEBUG STATE ===');
    print('👤 User ID: $_userId');
    print('📅 Days Remaining: $daysRemaining');
    print('📱 SharedPreferences Keys:');

    for (String key in keys) {
      final value = prefs.get(key);
      print('   - $key: $value');
    }

    // Check if user exists in admin database
    if (_userId != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection(_usersCollection)
            .doc(_userId)
            .get();

        if (userDoc.exists) {
          print('✅ User exists in admin database');
          print('📊 User data: ${userDoc.data()}');
        } else {
          print('❌ User NOT FOUND in admin database');
        }
      } catch (e) {
        print('❌ Error checking admin database: $e');
      }
    }

    print('===================================');
  }

  Future<void> debugSetTrialToLastDay() async {
    final prefs = await SharedPreferences.getInstance();

    // Set trial start to 6 days ago (so today is the 7th/last day)
    final sixDaysAgo = DateTime.now().subtract(Duration(days: 6));
    await prefs.setString(_trialStartKey, sixDaysAgo.toIso8601String());
    await prefs.setBool(_purchasedKey, false);

    await _calculateTrialDays();

    print('🔄 DEBUG: Trial set to LAST DAY (should show 1 day remaining)');
    print('📅 DEBUG: Trial start set to: $sixDaysAgo');
    await debugPrintState();

    notifyListeners();
  }

  Future<void> debugSetTrialExpired() async {
    final prefs = await SharedPreferences.getInstance();

    // Set trial start to 8 days ago (trial expired)
    final eightDaysAgo = DateTime.now().subtract(Duration(days: 8));
    await prefs.setString(_trialStartKey, eightDaysAgo.toIso8601String());
    await prefs.setBool(_purchasedKey, false);

    await _calculateTrialDays();

    print('🔄 DEBUG: Trial set to EXPIRED');
    print('📅 DEBUG: Trial start set to: $eightDaysAgo');
    await debugPrintState();

    notifyListeners();
  }

  Future<void> debugResetTrial() async {
    print('🔄 DEBUG: Resetting trial to Day 1 - Clearing all data');

    // Clear ALL SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    print('✅ DEBUG: SharedPreferences completely cleared');

    // Reset all state variables
    _userId = null;
    daysRemaining = 0;
    _isLoading = true;

    // Force reinitialization to create new user
    await _initialize();

    print(
        '✅ DEBUG: Trial reset complete - New user should be created in admin database');
    await debugPrintState();

    notifyListeners();
  }

  Future<void> debugCheckFirebaseConnection() async {
    print('🔍 Checking Firebase connection...');

    try {
      // Test write
      final testDocRef =
          FirebaseFirestore.instance.collection('connection_test').doc('test');
      await testDocRef.set({
        'testTime': FieldValue.serverTimestamp(),
        'message': 'Firebase connection test',
      });

      // Test read
      final testDoc = await testDocRef.get();

      if (testDoc.exists) {
        print('✅ Firebase connection: SUCCESS');
        print('✅ Can read/write to Firestore');

        // Clean up test document
        await testDocRef.delete();
      } else {
        print('❌ Firebase connection: Could not read test document');
      }

      // Check if users collection is accessible
      final usersQuery = await FirebaseFirestore.instance
          .collection(_usersCollection)
          .limit(1)
          .get();

      print('✅ Users collection is accessible');
      print('📊 Total users in database: ${usersQuery.size}');
    } catch (e) {
      print('❌ Firebase connection: FAILED - $e');

      if (e is FirebaseException) {
        print('❌ Firebase error code: ${e.code}');
        print('❌ Firebase error message: ${e.message}');
      }
    }
  }

  void _forceAppRefresh() {
    Future.delayed(Duration(milliseconds: 100), () {
      notifyListeners();
    });
  }
}
