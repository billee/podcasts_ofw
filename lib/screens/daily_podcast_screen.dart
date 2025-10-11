import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../services/audio_player_service.dart';
import '../services/iap_simulation_service.dart';
import '../models/app_models.dart';
import '../app/global_context.dart';
import 'settings_screen.dart';

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
  final AudioPlayerService _audioService = AudioPlayerService();
  final List<Podcast> _podcasts = [];
  bool _isLoading = true;

  // Get Supabase URL from environment variables
  String get _supabaseUrl => dotenv.env['SUPABASE_URL']!;

  // Get today's podcast based on the day of the month
  Podcast get _todayPodcast {
    if (_podcasts.isEmpty) {
      return Podcast(
        title: 'No Podcast Available',
        description: 'Please check back later for new podcasts.',
        audioFileName: '',
        duration: '0:00',
      );
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
    _fetchPodcasts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GlobalContext.context = context;
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
          _podcasts.clear();
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _podcasts.clear();
        _podcasts.addAll(querySnapshot.docs.map((doc) {
          return Podcast.fromFirestore(doc.data());
        }));
        _isLoading = false;
      });

      print('Loaded ${_podcasts.length} podcasts into app');
    } catch (e) {
      print('Error fetching podcasts: $e');
      setState(() {
        _isLoading = false;
        _podcasts.clear();
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
      if (_audioService.playerState == PlayerState.playing) {
        await _audioService.pause();
      } else if (_audioService.playerState == PlayerState.paused) {
        await _audioService.resume();
      } else {
        final podcast = _todayPodcast;
        final audioFileName = podcast.audioFileName;

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
        await _audioService.play(audioUrl);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing: ${podcast.title}'),
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
    }
  }

  Future<void> _stop() async {
    await _audioService.stop();
  }

  Future<void> _seek(double value) async {
    if (_audioService.duration.inSeconds == 0) return;
    final newPosition = _audioService.duration * value;
    await _audioService.seek(newPosition);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iapService = Provider.of<IAPSimulationService>(context);

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
                    // Show different icon based on subscription status
                    FutureBuilder<AppAccessState>(
                      future: iapService.getAccessState(),
                      builder: (context, snapshot) {
                        final hasAccess =
                            snapshot.data == AppAccessState.hasAccess;
                        return Icon(
                          hasAccess
                              ? Icons.workspace_premium
                              : Icons.headphones,
                          size: 70,
                          color: Colors.white,
                        );
                      },
                    ),
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
              // Show premium badge if subscribed
              FutureBuilder<AppAccessState>(
                future: iapService.getAccessState(),
                builder: (context, snapshot) {
                  final hasAccess = snapshot.data == AppAccessState.hasAccess;
                  if (hasAccess) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Icon(
                        Icons.workspace_premium,
                        color: Colors.amber,
                        size: 28,
                      ),
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
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
                  // Show premium badge next to title if subscribed
                  FutureBuilder<AppAccessState>(
                    future: iapService.getAccessState(),
                    builder: (context, snapshot) {
                      final hasAccess =
                          snapshot.data == AppAccessState.hasAccess;
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              podcast.title,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (hasAccess)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(
                                Icons.verified,
                                color: Colors.blue,
                                size: 28,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      _buildMetadata(Icons.schedule, podcast.duration),
                      SizedBox(width: 16),
                      _buildMetadata(Icons.calendar_today, _getFormattedDate()),
                      // Show subscription status
                      FutureBuilder<AppAccessState>(
                        future: iapService.getAccessState(),
                        builder: (context, snapshot) {
                          final hasAccess =
                              snapshot.data == AppAccessState.hasAccess;
                          if (hasAccess) {
                            return Row(
                              children: [
                                SizedBox(width: 16),
                                _buildMetadata(
                                    Icons.workspace_premium, 'Subscribed'),
                              ],
                            );
                          }
                          return SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  Text(
                    podcast.description,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 32),
                  StreamBuilder<Duration>(
                    stream: _audioService.durationStream,
                    builder: (context, durationSnapshot) {
                      return StreamBuilder<Duration>(
                        stream: _audioService.positionStream,
                        builder: (context, positionSnapshot) {
                          return StreamBuilder<PlayerState>(
                            stream: _audioService.playerStateStream,
                            builder: (context, stateSnapshot) {
                              return _buildAudioPlayer(
                                duration:
                                    durationSnapshot.data ?? Duration.zero,
                                position:
                                    positionSnapshot.data ?? Duration.zero,
                                playerState:
                                    stateSnapshot.data ?? PlayerState.stopped,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
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

  Widget _buildAudioPlayer({
    required Duration duration,
    required Duration position,
    required PlayerState playerState,
  }) {
    final progress =
        duration.inSeconds > 0 ? position.inSeconds / duration.inSeconds : 0.0;

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
                    _formatDuration(position),
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    _formatDuration(duration),
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
                      playerState == PlayerState.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 36,
                      color: Colors.white,
                    ),
                    onPressed: _playPause,
                    tooltip:
                        playerState == PlayerState.playing ? 'Pause' : 'Play',
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
              _getPlayerStatus(playerState),
              style: TextStyle(
                color: _getStatusColor(playerState),
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

  String _getPlayerStatus(PlayerState playerState) {
    switch (playerState) {
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

  Color _getStatusColor(PlayerState playerState) {
    switch (playerState) {
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
