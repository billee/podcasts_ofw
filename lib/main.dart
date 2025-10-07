import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
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

  // Podcast data - different podcast for each day
  final List<Map<String, String>> _podcasts = [
    {
      'title': 'Morning Motivation',
      'description':
          'Start your day with positive energy and inspiration. This podcast will help you set the right tone for a productive day ahead with actionable tips and motivational stories.',
      'audioPath':
          'audio/E1_Hindi_Lang_Padala_Ang_Mas_Malalim_na_Pagkilala_sa_OFW.m4a',
      'duration': '15:30',
    },
    {
      'title': 'Tech News Daily',
      'description':
          'Stay updated with the latest in technology, from AI breakthroughs to new gadget releases. Perfect for tech enthusiasts and professionals.',
      'audioPath': 'audio/E2_Mindfulness_Minute_Para_sa_OFW.m4a',
      'duration': '12:45',
    },
    {
      'title': 'Mindfulness Meditation',
      'description':
          'Take a break and center yourself with this guided meditation session. Reduce stress and improve focus in just 20 minutes.',
      'audioPath': 'audio/meditation.mp3',
      'duration': '20:15',
    },
    {
      'title': 'Business Insights',
      'description':
          'Learn from successful entrepreneurs and business leaders. Get practical advice for growing your career or business.',
      'audioPath': 'audio/E3_PD_442_Ang_Pundasyon_ng_OFW_Phenomenon.m4a',
      'duration': '18:20',
    },
    {
      'title': 'Health & Wellness',
      'description':
          'Evidence-based health tips and wellness strategies to help you live your best life.',
      'audioPath':
          'audio/E4_Ultimate_Gabay_OFW_Karapatan_sa_Kontrata,_Financial_Literacy.m4a',
      'duration': '14:50',
    },
  ];

  // Get today's podcast based on the day of the month
  Map<String, String> get _todayPodcast {
    final today = DateTime.now();
    final index = (today.day - 1) % _podcasts.length;
    return _podcasts[index];
  }

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
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
      // When audio completes, reset everything
      setState(() {
        _playerState = PlayerState.stopped;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _playPause() async {
    try {
      if (_playerState == PlayerState.playing) {
        await _audioPlayer.pause();
      } else if (_playerState == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        // For stopped or completed state, play from beginning
        await _audioPlayer.play(AssetSource(_todayPodcast['audioPath']!));
      }
    } catch (e) {
      print('Error playing audio: $e');
      // Show a user-friendly error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play audio. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      // Reset state
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
    // Reset everything
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
                    podcast['title']!,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 16),

                  // Podcast metadata
                  Row(
                    children: [
                      _buildMetadata(Icons.schedule, podcast['duration']!),
                      SizedBox(width: 16),
                      _buildMetadata(Icons.calendar_today, _getFormattedDate()),
                    ],
                  ),
                  SizedBox(height: 24),

                  // Description
                  Text(
                    podcast['description']!,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 32),

                  // Audio Player
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
            // Progress bar
            Slider(
              value: progress.isNaN ? 0.0 : progress,
              onChanged: _seek,
              activeColor: Colors.blue,
              inactiveColor: Colors.grey[300],
            ),

            // Time labels
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

            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Stop button
                IconButton(
                  icon: Icon(Icons.stop, size: 28),
                  onPressed: _stop,
                  color: Colors.red,
                  tooltip: 'Stop',
                ),

                SizedBox(width: 16),

                // Play/Pause button
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

                // Restart button
                IconButton(
                  icon: Icon(Icons.replay, size: 28),
                  onPressed: _stop,
                  color: Colors.blue,
                  tooltip: 'Restart',
                ),
              ],
            ),

            SizedBox(height: 16),

            // Status
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
