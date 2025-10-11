import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  try {
    // Initialize Firebase (for podcasts data only)
    await Firebase.initializeApp();
    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization error: $e');
  }

  // Initialize Supabase (for storage only)
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppPurchaseService(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Podcast',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AppAccessWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppAccessWrapper extends StatefulWidget {
  @override
  _AppAccessWrapperState createState() => _AppAccessWrapperState();
}

class _AppAccessWrapperState extends State<AppAccessWrapper> {
  @override
  Widget build(BuildContext context) {
    final purchaseService = Provider.of<AppPurchaseService>(context);

    return FutureBuilder<AppAccessState>(
      future: purchaseService.getAccessState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.grey[50],
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text(
                    'Checking access...',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        final accessState = snapshot.data ?? AppAccessState.trialExpired;

        // Print for debugging
        print('Current access state: $accessState');

        switch (accessState) {
          case AppAccessState.hasAccess:
            return DailyPodcastScreen();
          case AppAccessState.inTrial:
            return DailyPodcastScreen(
              showTrialBanner: true,
              daysRemaining: purchaseService.daysRemaining,
            );
          case AppAccessState.trialExpired:
            return SubscriptionScreen();
          default:
            return SubscriptionScreen();
        }
      },
    );
  }
}

enum AppAccessState {
  hasAccess, // User has purchased subscription
  inTrial, // User is in trial period
  trialExpired, // Trial expired, needs to purchase
}

class AppPurchaseService with ChangeNotifier {
  final String _subscriptionProductId = 'podcast_subscription_monthly';
  final String _trialStartKey = 'trial_start_date';
  final String _purchasedKey = 'has_purchased';

  String? _userId;
  final String _userIdKey = 'user_id';

  int daysRemaining = 0;
  bool _isLoading = true;
  bool _simulateIAP = true; // Set to true to simulate IAP without Play Store

  // IAP related
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  List<ProductDetails> _products = [];

  AppPurchaseService() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _initializeTrial();
    await _initializeUser();

    if (!_simulateIAP) {
      await _setupIAPListeners();
      await _loadProducts();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _initializeUser() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if we already have a user ID
    _userId = prefs.getString(_userIdKey);

    if (_userId == null) {
      // Create a new user ID
      _userId = _generateUserId();
      await prefs.setString(_userIdKey, _userId!);
      print('New user created: $_userId');

      // Create user document in Firestore
      await _createUserDocument();
    } else {
      print('Existing user: $_userId');
      // Update last active timestamp
      await _updateUserLastActive();
    }
  }

  String _generateUserId() {
    // Generate a unique user ID (you can use a package like uuid for production)
    return 'user_${DateTime.now().millisecondsSinceEpoch}_${_randomString(6)}';
  }

  String _randomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  Future<void> _createUserDocument() async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).set({
        'userId': _userId,
        'createdAt': FieldValue.serverTimestamp(),
        'trialStartDate': FieldValue.serverTimestamp(),
        'isSubscribed': false,
        'lastActive': FieldValue.serverTimestamp(),
        'appVersion': '1.0.0',
        'platform': 'android', // or get from device info
      });
      print('User document created in Firestore');
    } catch (e) {
      print('Error creating user document: $e');
    }
  }

  Future<void> _updateUserLastActive() async {
    if (_userId == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).update({
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating user last active: $e');
    }
  }

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

      // Calculate the difference in days
      final difference = trialEnd.difference(now);
      daysRemaining = difference.inDays;

      // If we're on the same day but trial hasn't ended, show 1 day remaining
      if (difference.inHours > 0 && difference.inDays == 0) {
        daysRemaining = 1; // Show 1 day remaining on the last day
      }

      if (daysRemaining < 0) daysRemaining = 0;

      print('Trial calculation:');
      print('- Trial start: $trialStart');
      print('- Trial end: $trialEnd');
      print('- Now: $now');
      print(
          '- Difference: ${difference.inDays} days, ${difference.inHours.remainder(24)} hours');
      print('- Days remaining: $daysRemaining');
    }
  }

  Future<void> _setupIAPListeners() async {
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        print('IAP not available on this device');
        return;
      }

      final purchaseUpdated = InAppPurchase.instance.purchaseStream;
      _subscription = purchaseUpdated.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription.cancel(),
        onError: (error) => print('IAP Stream Error: $error'),
      );
    } catch (e) {
      print('Error setting up IAP listeners: $e');
    }
  }

  Future<void> _loadProducts() async {
    try {
      final ProductDetailsResponse response = await InAppPurchase.instance
          .queryProductDetails({_subscriptionProductId});

      if (response.notFoundIDs.isNotEmpty) {
        print('IAP Product not found: ${response.notFoundIDs}');
      }

      _products = response.productDetails;
      print('Loaded products: ${_products.length}');
    } catch (e) {
      print('Error loading products: $e');
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      _handlePurchase(purchaseDetails);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.status == PurchaseStatus.purchased ||
        purchaseDetails.status == PurchaseStatus.restored) {
      await _activateSubscription();
      await InAppPurchase.instance.completePurchase(purchaseDetails);
    }

    if (purchaseDetails.status == PurchaseStatus.error) {
      print('Purchase error: ${purchaseDetails.error}');
      if (GlobalContext.context.mounted) {
        ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: ${purchaseDetails.error?.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _activateSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_purchasedKey, true);

    // Update Firestore with subscription info
    await _updateSubscriptionStatus(true);

    print('Subscription activated successfully for user: $_userId');

    if (GlobalContext.context.mounted) {
      ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
        SnackBar(
          content: Text('Subscription activated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }

    notifyListeners();
  }

  Future<void> _updateSubscriptionStatus(bool isSubscribed) async {
    if (_userId == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).update({
        'isSubscribed': isSubscribed,
        'subscriptionActivatedAt':
            isSubscribed ? FieldValue.serverTimestamp() : null,
        'lastActive': FieldValue.serverTimestamp(),
      });
      print('Subscription status updated in Firestore: $isSubscribed');
    } catch (e) {
      print('Error updating subscription status: $e');
    }
  }

  Future<AppAccessState> getAccessState() async {
    final prefs = await SharedPreferences.getInstance();

    // First check local storage for quick access
    final hasPurchased = prefs.getBool(_purchasedKey) ?? false;
    if (hasPurchased) {
      return AppAccessState.hasAccess;
    }

    // For more reliability, we can check Firestore
    try {
      if (_userId != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;

          // Check subscription status from Firestore
          if (userData['isSubscribed'] == true) {
            // Update local storage to match
            await prefs.setBool(_purchasedKey, true);
            return AppAccessState.hasAccess;
          }

          // Check trial status from Firestore
          final trialStart = (userData['trialStartDate'] as Timestamp).toDate();
          final trialEnd = trialStart.add(Duration(days: 7));
          final now = DateTime.now();

          if (now.isBefore(trialEnd)) {
            await _calculateTrialDays();
            return AppAccessState.inTrial;
          }
        }
      }
    } catch (e) {
      print('Error checking access from Firestore: $e');
      // Fall back to local storage if Firestore fails
    }

    // Fallback to local storage check
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

  Future<void> purchaseSubscription() async {
    if (_simulateIAP) {
      // Simulate IAP purchase without Play Store
      print('SIMULATING IAP PURCHASE');
      await _activateSubscription();
      return;
    }

    try {
      if (_products.isEmpty) {
        await _loadProducts();

        if (_products.isEmpty) {
          if (GlobalContext.context.mounted) {
            ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
              SnackBar(
                content:
                    Text('Subscription not available. Please try again later.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      final purchaseParam = PurchaseParam(productDetails: _products.first);
      await InAppPurchase.instance.buyConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      print('Purchase error: $e');
      if (GlobalContext.context.mounted) {
        ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
          SnackBar(
            content: Text('Error starting purchase: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> restorePurchases() async {
    if (_simulateIAP) {
      // Simulate restore purchases
      print('SIMULATING RESTORE PURCHASES');
      final prefs = await SharedPreferences.getInstance();
      final hasPurchased = prefs.getBool(_purchasedKey) ?? false;

      if (hasPurchased) {
        if (GlobalContext.context.mounted) {
          ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
            SnackBar(
              content: Text('Purchase restored successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
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
      return;
    }

    try {
      if (GlobalContext.context.mounted) {
        ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
          SnackBar(
            content: Text('Restoring purchases...'),
            backgroundColor: Colors.blue,
          ),
        );
      }

      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      print('Restore purchases error: $e');
      if (GlobalContext.context.mounted) {
        ScaffoldMessenger.of(GlobalContext.context).showSnackBar(
          SnackBar(
            content: Text('Error restoring purchases: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // DEBUG METHODS
  Future<void> debugPrintSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    print('=== SHAREDPREFERENCES DEBUG INFO ===');
    for (String key in keys) {
      final value = prefs.get(key);
      print('$key: $value (${value.runtimeType})');
    }
    print('====================================');
  }

  Future<void> debugSetTrialToLastDay() async {
    final prefs = await SharedPreferences.getInstance();

    // Set trial start to 6 days ago (so today is the 7th/last day)
    // This should give 1 day remaining, not 0
    final sixDaysAgo = DateTime.now().subtract(Duration(days: 6));
    await prefs.setString(_trialStartKey, sixDaysAgo.toIso8601String());
    await prefs.setBool(_purchasedKey, false); // Ensure not purchased

    // Force recalculate days
    await _calculateTrialDays();

    print('DEBUG: Trial set to LAST DAY (should show 1 day remaining)');
    print('DEBUG: Actual days remaining: $daysRemaining');
    await debugPrintSharedPreferences();

    notifyListeners();

    // Force navigation
    _forceAppRefresh();
  }

  Future<void> debugSetTrialExpired() async {
    final prefs = await SharedPreferences.getInstance();

    // Set trial start to 8 days ago (trial expired)
    final eightDaysAgo = DateTime.now().subtract(Duration(days: 8));
    await prefs.setString(_trialStartKey, eightDaysAgo.toIso8601String());
    await prefs.setBool(_purchasedKey, false); // Ensure not purchased

    await _calculateTrialDays();

    print('DEBUG: Trial set to EXPIRED');
    await debugPrintSharedPreferences();

    notifyListeners();

    // Force navigation
    _forceAppRefresh();
  }

  Future<void> debugResetTrial() async {
    final prefs = await SharedPreferences.getInstance();

    // Set trial to today (fresh start)
    await prefs.setString(_trialStartKey, DateTime.now().toIso8601String());
    await prefs.setBool(_purchasedKey, false); // Ensure not purchased

    await _calculateTrialDays();

    print('DEBUG: Trial reset to DAY 1 (7 days remaining)');
    await debugPrintSharedPreferences();

    notifyListeners();

    // Force navigation
    _forceAppRefresh();
  }

  Future<void> debugSimulatePurchase() async {
    await _activateSubscription();
  }

  void _forceAppRefresh() {
    // This will trigger the AppAccessWrapper to rebuild
    // We use a small delay to ensure the state is updated first
    Future.delayed(Duration(milliseconds: 100), () {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Helper class to get context for snackbars
class GlobalContext {
  static late BuildContext context;
}

class SubscriptionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    GlobalContext.context = context;
    final purchaseService = Provider.of<AppPurchaseService>(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Header section
              Icon(
                Icons.workspace_premium,
                size: 80,
                color: Colors.blue,
              ),
              SizedBox(height: 16),
              Text(
                'Unlock Full Access',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Your 7-day free trial has ended. Subscribe now to continue enjoying daily podcasts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 24),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildFeatureList(),
                      SizedBox(height: 24),
                      _buildPricingCard(),
                    ],
                  ),
                ),
              ),

              // Fixed buttons at bottom
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => purchaseService.purchaseSubscription(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Subscribe Now - \$4.99/month',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SizedBox(height: 12),
              TextButton(
                onPressed: () => purchaseService.restorePurchases(),
                child: Text(
                  'Restore Purchase',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
              // Debug button
              TextButton(
                onPressed: () {
                  purchaseService.debugResetTrial();
                  // Force rebuild by using a hack - navigate away and back
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => MyApp()),
                    (route) => false,
                  );
                },
                child: Text(
                  'DEBUG: Reset Trial',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    final features = [
      'Daily podcast episodes',
      'High-quality audio',
      'Offline listening',
      'No advertisements',
      'Exclusive content',
      'Cancel anytime',
    ];

    return Column(
      children: features
          .map((feature) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildPricingCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Monthly Subscription',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '\$4.99 / month',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Auto-renews monthly',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final purchaseService = Provider.of<AppPurchaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.workspace_premium),
            title: Text('Subscription'),
            subtitle: FutureBuilder<AppAccessState>(
              future: purchaseService.getAccessState(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final state = snapshot.data!;
                  return Text(state == AppAccessState.hasAccess
                      ? 'Active Subscription'
                      : state == AppAccessState.inTrial
                          ? 'Free Trial Active'
                          : 'No Active Subscription');
                }
                return Text('Checking status...');
              },
            ),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => SubscriptionScreen()));
            },
          ),
          ListTile(
            leading: Icon(Icons.restore),
            title: Text('Restore Purchases'),
            onTap: () => purchaseService.restorePurchases(),
          ),
          ListTile(
            leading: Icon(Icons.help),
            title: Text('Help & Support'),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Help & Support'),
                  content: Text(
                      'For subscription issues, please contact support@yourapp.com'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
          // Debug section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('DEBUG',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: Icon(Icons.bug_report),
            title: Text('Debug SharedPreferences'),
            onTap: () => purchaseService.debugPrintSharedPreferences(),
          ),
          ListTile(
            leading: Icon(Icons.refresh),
            title: Text('Reset Trial to Day 1'),
            onTap: () async {
              await purchaseService.debugResetTrial();
              // Force navigation back
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => MyApp()),
                (route) => false,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.warning),
            title: Text('Set Trial to Last Day'),
            onTap: () async {
              await purchaseService.debugSetTrialToLastDay();
              // Force navigation back
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => MyApp()),
                (route) => false,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.error),
            title: Text('Set Trial Expired'),
            onTap: () async {
              await purchaseService.debugSetTrialExpired();
              // Force navigation back
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => MyApp()),
                (route) => false,
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.sim_card),
            title: Text('Simulate Purchase'),
            onTap: () => purchaseService.debugSimulatePurchase(),
          ),
        ],
      ),
    );
  }
}

class DailyPodcastScreen extends StatefulWidget {
  final bool showTrialBanner;
  final int daysRemaining;

  const DailyPodcastScreen({
    Key? key,
    this.showTrialBanner = false,
    this.daysRemaining = 0,
  }) : super(key: key);

  @override
  _DailyPodcastScreenState createState() => _DailyPodcastScreenState();
}

class _DailyPodcastScreenState extends State<DailyPodcastScreen> {
  AudioPlayer _audioPlayer = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isSeeking = false;
  List<Map<String, dynamic>> _podcasts = [];
  bool _isLoading = true;

  // Get Supabase URL from environment variables
  String get _supabaseUrl => dotenv.env['SUPABASE_URL']!;

  // Get today's podcast based on the day of the month
  Map<String, dynamic> get _todayPodcast {
    if (_podcasts.isEmpty) {
      return {
        'title': 'No Podcast Available',
        'description': 'Please check back later for new podcasts.',
        'audioFileName': '',
        'duration': '0:00',
      };
    }
    final today = DateTime.now();
    final index = (today.day - 1) % _podcasts.length;
    return _podcasts[index];
  }

  // Get the public URL for a podcast file from Supabase storage
  String _getAudioUrl(String audioFileName) {
    String cleanFileName = audioFileName;
    if (audioFileName.contains('/')) {
      cleanFileName = audioFileName.split('/').last;
    }
    final url =
        '$_supabaseUrl/storage/v1/object/public/podcasts/$cleanFileName';
    print('Generated audio URL: $url');
    return url;
  }

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
    _fetchPodcasts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalContext.context = context;
    });
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return; // Prevent setState if widget is disposed
      if (!_isSeeking) {
        setState(() {
          _playerState = state;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return; // Prevent setState if widget is disposed
      setState(() {
        _duration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return; // Prevent setState if widget is disposed
      if (!_isSeeking) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (!mounted) return; // Prevent setState if widget is disposed
      setState(() {
        _playerState = PlayerState.stopped;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _fetchPodcasts() async {
    try {
      print('Fetching podcasts from Firestore...');

      final querySnapshot = await FirebaseFirestore.instance
          .collection('podcasts')
          .where('isActive', isEqualTo: true)
          .get();

      print('Found ${querySnapshot.docs.length} podcasts');

      if (querySnapshot.docs.isEmpty) {
        print('No active podcasts found in Firestore');
        setState(() {
          _podcasts = [];
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _podcasts = querySnapshot.docs.map((doc) {
          final data = doc.data();
          print('Raw Firestore data: $data');

          // Try different possible field names for audio file
          String audioFileName = '';
          if (data['audioFilename'] != null) {
            audioFileName = data['audioFilename'];
          } else if (data['audioFileName'] != null) {
            audioFileName = data['audioFileName'];
          } else if (data['audioFile'] != null) {
            audioFileName = data['audioFile'];
          } else if (data['fileName'] != null) {
            audioFileName = data['fileName'];
          } else if (data['file'] != null) {
            audioFileName = data['file'];
          } else if (data['audio'] != null) {
            audioFileName = data['audio'];
          }

          // Fix the file name to match what's in Supabase storage
          if (audioFileName == 'podcast_1759978000157_ang_kakaba.mpg') {
            audioFileName = 'podcast_1759978000157_ang_kakalba.mp3';
          }

          print('Resolved audioFileName: $audioFileName');

          return {
            'title': data['title'] ?? 'Untitled Podcast',
            'description': data['description'] ?? 'No description available.',
            'audioFileName': audioFileName,
            'duration': data['duration'] ?? '0:00',
          };
        }).toList();
        _isLoading = false;
      });

      print('Loaded ${_podcasts.length} podcasts into app');
    } catch (e) {
      print('Error fetching podcasts: $e');
      setState(() {
        _isLoading = false;
        _podcasts = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load podcasts. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playPause() async {
    try {
      if (_playerState == PlayerState.playing) {
        await _audioPlayer.pause();
      } else if (_playerState == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        final podcast = _todayPodcast;
        final audioFileName = podcast['audioFileName']?.toString() ?? '';

        print('Attempting to play: $audioFileName');

        if (audioFileName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audio file not available.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final audioUrl = _getAudioUrl(audioFileName);

        // Test if we can generate a valid URL
        print('Audio URL: $audioUrl');

        // Try to play the audio
        await _audioPlayer.play(UrlSource(audioUrl));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing: ${podcast['title']}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error playing audio: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play audio. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _playerState = PlayerState.stopped;
        _position = Duration.zero;
      });
    }
  }

  Future<void> _stop() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      print('Error stopping audio: $e');
    }
    setState(() {
      _playerState = PlayerState.stopped;
      _position = Duration.zero;
    });
  }

  Future<void> _seek(double value) async {
    if (_duration.inSeconds == 0) return;

    final newPosition = _duration * value;
    setState(() {
      _isSeeking = true;
      _position = newPosition;
    });

    try {
      await _audioPlayer.seek(newPosition);
    } catch (e) {
      print('Error seeking: $e');
    }

    setState(() {
      _isSeeking = false;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    // Also cancel any other subscriptions if you have them
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Loading podcasts...',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final podcast = _todayPodcast;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          if (widget.showTrialBanner) _buildTrialBanner(),
          SliverAppBar(
            expandedHeight: 250.0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.blue[800]!, Colors.purple[700]!],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.headphones, size: 70, color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      "Today's Podcast",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _getFormattedDate(),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.settings, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => SettingsScreen()));
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    podcast['title']?.toString() ?? 'No Title',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      _buildMetadata(Icons.schedule,
                          podcast['duration']?.toString() ?? '0:00'),
                      SizedBox(width: 16),
                      _buildMetadata(Icons.calendar_today, _getFormattedDate()),
                    ],
                  ),
                  SizedBox(height: 24),
                  Text(
                    podcast['description']?.toString() ??
                        'No description available.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 32),
                  _buildAudioPlayer(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => SettingsScreen()));
        },
        child: Icon(Icons.settings),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildTrialBanner() {
    return SliverToBoxAdapter(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(12),
        color: Colors.orange[50],
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Text(
              '${widget.daysRemaining} days of free trial remaining',
              style: TextStyle(
                color: Colors.orange[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadata(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildAudioPlayer() {
    final progress = _duration.inSeconds > 0
        ? _position.inSeconds / _duration.inSeconds
        : 0.0;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Slider(
              value: progress.isNaN ? 0.0 : progress,
              onChanged: _seek,
              activeColor: Colors.blue,
              inactiveColor: Colors.grey[300],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.stop, size: 28),
                  onPressed: _stop,
                  color: Colors.red,
                  tooltip: 'Stop',
                ),
                SizedBox(width: 16),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.blue[600]!, Colors.blue[800]!],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _playerState == PlayerState.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 36,
                      color: Colors.white,
                    ),
                    onPressed: _playPause,
                    tooltip:
                        _playerState == PlayerState.playing ? 'Pause' : 'Play',
                  ),
                ),
                SizedBox(width: 16),
                IconButton(
                  icon: Icon(Icons.replay, size: 28),
                  onPressed: _stop,
                  color: Colors.blue,
                  tooltip: 'Restart',
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              _getPlayerStatus(),
              style: TextStyle(
                color: _getStatusColor(),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final weekdays = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];

    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  String _getPlayerStatus() {
    switch (_playerState) {
      case PlayerState.playing:
        return 'Now Playing';
      case PlayerState.paused:
        return 'Paused';
      case PlayerState.stopped:
        return 'Stopped';
      case PlayerState.completed:
        return 'Completed';
      default:
        return 'Ready to Play';
    }
  }

  Color _getStatusColor() {
    switch (_playerState) {
      case PlayerState.playing:
        return Colors.green;
      case PlayerState.paused:
        return Colors.orange;
      case PlayerState.stopped:
        return Colors.grey;
      case PlayerState.completed:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
