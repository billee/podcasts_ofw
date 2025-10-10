import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  try {
    // Initialize Firebase
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

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Podcast',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: DailyPodcastScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class DailyPodcastScreen extends StatefulWidget {
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
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!_isSeeking) {
        setState(() {
          _playerState = state;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() {
        _duration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (!_isSeeking) {
        setState(() {
          _position = position;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
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
            audioFileName = data['audioFilename']; // Note: lowercase 'n'
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
