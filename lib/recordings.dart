import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart'; // Add this to pubspec.yaml if not already added
import 'recording_model.dart';
import 'package:just_audio/just_audio.dart'; // Add this dependency to pubspec.yaml

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> with SingleTickerProviderStateMixin {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final List<RecordingModel> _recordings = [];
  String? _currentlyPlayingPath;
  bool _isPlayerReady = false;
  
  // Map to store audio durations
  final Map<String, Duration> _durations = {};
  
  // Animation controller for smooth transitions
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  
  // Map to group recordings by month/year
  Map<String, List<RecordingModel>> _groupedRecordings = {};

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadRecordings();
    
    // Initialize animation controller
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    setState(() {
      _isPlayerReady = true;
    });
  }

  Future<void> _loadRecordings() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');

      if (await recordingsDir.exists()) {
        final files = recordingsDir.listSync().whereType<File>().toList();
        
        // Get all audio files
        final audioFiles = files.where((file) => 
          file.path.endsWith('.aac') || file.path.endsWith('.mp3')).toList();
          
        List<RecordingModel> loadedRecordings = [];
        
        for (var file in audioFiles) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          final nameWithoutExtension = fileName.split('.').first;
          
          // Check if a corresponding JSON metadata file exists
          final metadataPath = '${recordingsDir.path}/$nameWithoutExtension.json';
          final metadataFile = File(metadataPath);
          
          if (await metadataFile.exists()) {
            // Load recording with transcription from metadata file
            try {
              final jsonString = await metadataFile.readAsString();
              final jsonMap = jsonDecode(jsonString);
              final recording = RecordingModel.fromJson(jsonMap);
              loadedRecordings.add(recording);
              
              // Get duration asynchronously
              _getDuration(recording.path);
              
            } catch (e) {
              debugPrint('Error loading metadata for $fileName: $e');
              // If metadata loading fails, create a basic recording model
              loadedRecordings.add(RecordingModel(
                name: nameWithoutExtension,
                path: file.path,
                date: file.lastModifiedSync(),
              ));
              
              // Get duration asynchronously
              _getDuration(file.path);
            }
          } else {
            // Create a basic recording model without transcription
            loadedRecordings.add(RecordingModel(
              name: nameWithoutExtension,
              path: file.path,
              date: file.lastModifiedSync(),
            ));
            
            // Get duration asynchronously
            _getDuration(file.path);
          }
        }

        // Sort by date (newest first)
        loadedRecordings.sort((a, b) => b.date.compareTo(a.date));
        
        // Group recordings by month and year
        _groupedRecordings = _groupRecordingsByMonthYear(loadedRecordings);
        
        setState(() {
          _recordings.clear();
          _recordings.addAll(loadedRecordings);
        });
      }
    } catch (e) {
      debugPrint('Error loading recordings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading recordings: $e')),
      );
    }
  }
  
  // Method to get the duration of an audio file using just_audio
  Future<void> _getDuration(String filePath) async {
    try {
      // Check if we've already gotten this duration
      if (_durations.containsKey(filePath)) {
        return;
      }
      
      // Create temporary audio player just to get duration
      final audioPlayer = AudioPlayer();
      await audioPlayer.setFilePath(filePath);
      final duration = audioPlayer.duration;
      
      if (duration != null) {
        setState(() {
          _durations[filePath] = duration;
        });
      }
      
      // Dispose of the temporary player
      await audioPlayer.dispose();
    } catch (e) {
      debugPrint('Error getting duration for $filePath: $e');
      // Use a default duration as fallback
      setState(() {
        _durations[filePath] = const Duration(seconds: 30); // Default to 30 seconds
      });
    }
  }

  Map<String, List<RecordingModel>> _groupRecordingsByMonthYear(List<RecordingModel> recordings) {
    final Map<String, List<RecordingModel>> grouped = {};
    
    for (var recording in recordings) {
      final date = recording.date;
      String key;
      
      // Current year recordings show only month, past years show "Month Year"
      if (date.year == DateTime.now().year) {
        key = DateFormat('MMMM').format(date); // Just month name for current year
      } else {
        key = DateFormat('MMMM yyyy').format(date); // Month and year for previous years
      }
      
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      
      grouped[key]!.add(recording);
    }
    
    return grouped;
  }

  Future<void> _playRecording(String filePath) async {
    if (!_isPlayerReady) {
      debugPrint('Player not ready in RecordingsScreen.');
      return;
    }

    if (_player.isPlaying) {
      await _player.stopPlayer();
      if (_currentlyPlayingPath == filePath) {
        setState(() {
          _currentlyPlayingPath = null;
        });
        return;
      }
    }

    try {
      // Determine codec based on file extension
      Codec codecToUse = Codec.aacADTS; // Default to AAC
      if (filePath.toLowerCase().endsWith('.mp3')) {
        codecToUse = Codec.mp3;
      }
      
      await _player.startPlayer(
        fromURI: filePath,
        codec: codecToUse,
        whenFinished: () {
          if (mounted) {
            setState(() {
              _currentlyPlayingPath = null;
            });
          }
        },
      );
      setState(() {
        _currentlyPlayingPath = filePath;
      });
      
      // If we don't have the duration yet, get it
      if (!_durations.containsKey(filePath)) {
        _getDuration(filePath);
      }
    } catch (e) {
      debugPrint('Error playing recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing recording: $e')),
        );
        setState(() {
          _currentlyPlayingPath = null;
        });
      }
    }
  }

  // Show delete confirmation dialog
  Future<void> _showDeleteConfirmationDialog(RecordingModel recording) async {
    final bool confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.grey[900],
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete recording?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Are you sure you want to delete "${recording.name}"?\nThis action can\'t be undone.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ) ?? false;

    if (confirmDelete) {
      await _deleteRecording(recording);
    }
  }

  Future<void> _deleteRecording(RecordingModel recording) async {
    final filePath = recording.path;
    
    // Stop playback if the file to be deleted is currently playing
    if (_currentlyPlayingPath == filePath) {
      await _player.stopPlayer();
      _currentlyPlayingPath = null;
    }
    
    try {
      // Delete the audio file
      final audioFile = File(filePath);
      if (await audioFile.exists()) {
        await audioFile.delete();
      }
      
      // Delete the metadata JSON file if it exists
      final nameWithoutExtension = filePath.split(Platform.pathSeparator).last.split('.').first;
      final directory = File(filePath).parent;
      final metadataPath = '${directory.path}/$nameWithoutExtension.json';
      final metadataFile = File(metadataPath);
      
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      
      // Remove duration from cache
      _durations.remove(filePath);
      
      // Update both the flat list and grouped map
      setState(() {
        _recordings.remove(recording);
        _groupedRecordings = _groupRecordingsByMonthYear(_recordings);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording deleted'),
          backgroundColor: Colors.grey[800],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error deleting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting recording: $e')),
      );
    }
  }

  // PIN/UNPIN FUNCTIONALITY
  Future<void> _togglePinStatus(RecordingModel recording) async {
    try {
      final nameWithoutExtension = recording.path.split(Platform.pathSeparator).last.split('.').first;
      final directory = File(recording.path).parent;
      final metadataPath = '${directory.path}/$nameWithoutExtension.json';
      final metadataFile = File(metadataPath);
      
      // Create updated recording with toggled pin status
      final updatedRecording = recording.copyWith(pinned: !recording.pinned);
      
      // Save updated metadata to file
      await metadataFile.writeAsString(jsonEncode(updatedRecording.toJson()));
      
      // Update the list
      setState(() {
        final index = _recordings.indexWhere((r) => r.path == recording.path);
        if (index >= 0) {
          _recordings[index] = updatedRecording;
        }
        
        // Update the grouped recordings as well
        _groupedRecordings = _groupRecordingsByMonthYear(_recordings);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedRecording.pinned ? 'Recording pinned to home screen' : 'Recording unpinned from home screen'
          ),
          backgroundColor: Colors.grey[800],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error updating pin status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating pin status: $e')),
      );
    }
  }

  void _showPinDialog(RecordingModel recording) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.grey[900],
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                recording.pinned ? 'Unpin Recording?' : 'Pin Recording?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                recording.pinned
                    ? 'Remove this recording from your home screen?'
                    : 'Add this recording to your home screen for quick access?',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: recording.pinned ? Colors.orange : Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _togglePinStatus(recording);
                      },
                      child: Text(recording.pinned ? 'Unpin' : 'Pin'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '--:--'; // Placeholder while loading
    }
    
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _player.closePlayer();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          // Swiping from left to right - go back to main screen
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('My Recordings'),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ),
        body: _recordings.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'No recordings yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Swipe right to go back to recording screen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _groupedRecordings.length,
                itemBuilder: (context, sectionIndex) {
                  final monthYear = _groupedRecordings.keys.toList()[sectionIndex];
                  final recordingsInGroup = _groupedRecordings[monthYear]!;
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section header for month/year
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Text(
                          monthYear,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      
                      // List of recordings for this month/year
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: recordingsInGroup.length,
                        itemBuilder: (context, index) {
                          final recording = recordingsInGroup[index];
                          final isPlaying = _currentlyPlayingPath == recording.path;
                          
                          // Format date as day and month
                          final dayMonth = DateFormat('d MMM').format(recording.date);
                          
                          // Get the actual duration from our map
                          final duration = _durations[recording.path];
                          
                          return GestureDetector(
                            onTapDown: (_) => _animController.forward(),
                            onTapUp: (_) => _animController.reverse(),
                            onTapCancel: () => _animController.reverse(),
                            onLongPress: () => _showPinDialog(recording),
                            child: AnimatedBuilder(
                              animation: _scaleAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _scaleAnimation.value,
                                  child: child,
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: InkWell(
                                  onTap: () => _playRecording(recording.path),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      recording.name,
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (recording.pinned)
                                                    Container(
                                                      margin: const EdgeInsets.only(left: 8),
                                                      child: const Icon(
                                                        Icons.push_pin,
                                                        color: Colors.blue,
                                                        size: 16,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                isPlaying ? Icons.pause : Icons.play_arrow,
                                                color: Colors.white,
                                              ),
                                              onPressed: () => _playRecording(recording.path),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              dayMonth,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.grey[400],
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _formatDuration(duration), // Using actual duration here
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey[400],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                GestureDetector(
                                                  onTap: () => _showDeleteConfirmationDialog(recording), // Changed to show confirmation
                                                  child: Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.grey[400],
                                                    size: 20,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}