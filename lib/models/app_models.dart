enum AppAccessState {
  hasAccess, // User has purchased subscription
  inTrial, // User is in trial period
  trialExpired, // Trial expired, needs to purchase
}

class Podcast {
  final String title;
  final String description;
  final String audioFileName;
  final String duration;

  Podcast({
    required this.title,
    required this.description,
    required this.audioFileName,
    required this.duration,
  });

  factory Podcast.fromFirestore(Map<String, dynamic> data) {
    // Helper function to safely convert any type to String
    String _toString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is int) return value.toString();
      if (value is double) return value.toString();
      if (value is bool) return value.toString();
      return value.toString();
    }

    // Try different possible field names for audio file
    String audioFileName = '';
    final audioFieldNames = [
      'audioFilename',
      'audioFileName',
      'audioFile',
      'fileName',
      'file',
      'audio'
    ];

    for (var fieldName in audioFieldNames) {
      if (data[fieldName] != null) {
        audioFileName = _toString(data[fieldName]);
        break;
      }
    }

    // Fix known file name discrepancies
    if (audioFileName == 'podcast_1759978000157_ang_kakaba.mpg') {
      audioFileName = 'podcast_1759978000157_ang_kakalba.mp3';
    }

    return Podcast(
      title: _toString(data['title']).isEmpty
          ? 'Untitled Podcast'
          : _toString(data['title']),
      description: _toString(data['description']).isEmpty
          ? 'No description available.'
          : _toString(data['description']),
      audioFileName: audioFileName,
      duration: _toString(data['duration']).isEmpty
          ? '0:00'
          : _toString(data['duration']),
    );
  }

  @override
  String toString() {
    return 'Podcast{title: $title, audioFileName: $audioFileName}';
  }
}
