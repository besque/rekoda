import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'recordings.dart';
import 'recording_model.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'map_view.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:intl/intl.dart'; // Make sure to add intl to pubspec.yaml

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> with SingleTickerProviderStateMixin {
  late RecorderController _recorderController;
  late PlayerController _playerController;
  bool _recorderIsReady = false;
  bool _playerIsReady = false;
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _recordingPath;
  String _tempRecordingPath = '';
  final String _tempFileName = 'temp_recording.aac';
  Position? _currentPosition;
  
  // Timer related variables
  Timer? _timer;
  int _recordingDuration = 0;
  bool _isPaused = false;
  
  final TextEditingController _recordingNameController = TextEditingController();
  
  // Pinned recordings list
  final List<RecordingModel> _pinnedRecordings = [];
  
  // Animation controller for smooth transitions
  AnimationController? _animController;
  // Animation<double>? _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize the recorder controller
    _recorderController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 44100;
    
    // Initialize player controller
    _playerController = PlayerController();
    
    // Initialize animation controller - changed to nullable and initialize here
    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    
   
    _setupTempPath();
    _initRecorder();
    _getCurrentLocation();
    _loadPinnedRecordings();
  }

  Future<void> _setupTempPath() async {
    try {
      final tempDir = await getTemporaryDirectory();
      setState(() {
        _tempRecordingPath = '${tempDir.path}/$_tempFileName';
      });
      debugPrint('Temp recording path set to: $_tempRecordingPath');
    } catch (e) {
      debugPrint('Error setting up temp path: $e');
      // Use a fallback path if needed
      setState(() {
        _tempRecordingPath = '/data/user/0/$_tempFileName';
      });
    }
  }

  Future<void> _initRecorder() async {
    try {
      // Request permissions first
      final micStatus = await Permission.microphone.request();
      
      if (micStatus != PermissionStatus.granted) {
        debugPrint('Microphone permission not granted: $micStatus');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to record audio.')),
        );
        setState(() {
          _recorderIsReady = false;
          _playerIsReady = false;
        });
        return;
      }

      // Check recorder permission
      bool hasPermission = await _recorderController.checkPermission();
      if (!hasPermission) {
        debugPrint('Recorder permission not granted');
        return;
      }

      // Create recordings directory if it doesn't exist
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      
      setState(() {
        _recorderIsReady = true;
        _playerIsReady = true;
      });
      
      debugPrint('Recorder initialized successfully: $_recorderIsReady');
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
      setState(() {
        _recorderIsReady = false;
        _playerIsReady = false;
      });
    }
  }

  // Load pinned recordings
  Future<void> _loadPinnedRecordings() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');

      if (await recordingsDir.exists()) {
        final files = recordingsDir.listSync().whereType<File>().toList();
        
        // Get all JSON metadata files
        final metadataFiles = files.where((file) => file.path.endsWith('.json')).toList();
        
        List<RecordingModel> pinnedRecordings = [];
        
        for (var file in metadataFiles) {
          try {
            final jsonString = await File(file.path).readAsString();
            final jsonMap = jsonDecode(jsonString);
            final recording = RecordingModel.fromJson(jsonMap);
            
            // Only add pinned recordings
            if (recording.pinned) {
              // Check if the audio file exists
              final audioFile = File(recording.path);
              if (await audioFile.exists()) {
                pinnedRecordings.add(recording);
              }
            }
          } catch (e) {
            debugPrint('Error loading metadata: $e');
          }
        }

        // Sort by date (newest first)
        pinnedRecordings.sort((a, b) => b.date.compareTo(a.date));
        
        setState(() {
          _pinnedRecordings.clear();
          _pinnedRecordings.addAll(pinnedRecordings);
        });
      }
    } catch (e) {
      debugPrint('Error loading pinned recordings: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
  
  void _resetTimer() {
    _stopTimer();
    setState(() {
      _recordingDuration = 0;
    });
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}.0';
  }

  Future<void> _startRecording() async {
    if (!_recorderIsReady) {
      debugPrint('Recorder not ready!');
      return;
    }
    
    try {
      // Start recording with audio_waveforms
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/$_tempFileName';
      
      await _recorderController.record(path: path);
      
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _tempRecordingPath = path;
      });
      
      _startTimer();
      
      debugPrint('Recording started at: $path');
    } catch (e) {
      debugPrint('Recording error: $e');
    }
  }

  Future<void> _pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    
    try {
      // Pause recorder
      await _recorderController.pause();
      
      // Stop timer
      _stopTimer();
      
      setState(() {
        _isPaused = true;
      });
      
      debugPrint('Recording paused');
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    if (!_isPaused) return;
    
    try {
      // Resume recorder
      await _recorderController.record();
      
      // Restart timer
      _startTimer();
      
      setState(() {
        _isPaused = false;
      });
      
      debugPrint('Recording resumed');
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording && !_isPaused) return;
    
    String? path = await _recorderController.stop();
    _resetTimer(); // Reset timer to 0 when saving
    
    setState(() {
      _isRecording = false;
      _isPaused = false;
      if (path != null) {
        _tempRecordingPath = path;
      }
    });
    
    // Show dialog to name and save the recording
    _showSaveRecordingDialog();
  }

  Future<void> _showSaveRecordingDialog() async {
    // Use AAC extension in default name
    _recordingNameController.text = 'Recording_${DateTime.now().toString().split('.')[0].replaceAll(':', '-').replaceAll(' ', '_')}'; 
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
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
                  'Save Recording',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _recordingNameController,
                  decoration: InputDecoration(
                    hintText: 'Recording name',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[800],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  autofocus: true,
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
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Delete temp recording
                          _deleteTempRecording();
                        },
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _saveRecording(_recordingNameController.text);
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveRecording(String name) async {
    if (name.isEmpty) {
      name = 'Recording_${DateTime.now().toString().split('.')[0].replaceAll(':', '-').replaceAll(' ', '_')}';
    }
    
    // Sanitize the filename
    name = name.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');
    
    try {
      // First, verify the temp recording exists
      final tempFile = File(_tempRecordingPath);
      if (!(await tempFile.exists())) {
        debugPrint('Temp recording file not found at: $_tempRecordingPath');
        return;
      }
      
      // Ensure the recordings directory exists
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      
      final savedPath = '${recordingsDir.path}/$name.aac'; // Keep same extension as temp file
      
      // Copy the audio file
      await tempFile.copy(savedPath);
      
      // Create a recording model with location (empty transcription)
      final recording = RecordingModel(
        name: name,
        path: savedPath,
        date: DateTime.now(),
        transcription: '',  // Empty transcription since we're not using it
        latitude: _currentPosition?.latitude,
        longitude: _currentPosition?.longitude,
      );
      
      // Save metadata to a separate JSON file
      final metadataPath = '${recordingsDir.path}/$name.json';
      final metadataFile = File(metadataPath);
      await metadataFile.writeAsString(jsonEncode(recording.toJson()));
      
      // Update the path for playback
      setState(() {
        _recordingPath = savedPath;
      });
      
      debugPrint('Recording successfully saved to: $savedPath');
      if (_currentPosition != null) {
        debugPrint('Location saved: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      }
    } catch (e) {
      debugPrint('Failed to save recording: $e');
    }
  }

  Future<void> _deleteTempRecording() async {
    try {
      final tempFile = File(_tempRecordingPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      // Silently handle the error
      debugPrint('Failed to delete temp recording: $e');
    }
  }

  Future<void> _playPinnedRecording(RecordingModel recording) async {
    if (_isPlaying) {
      await _playerController.stopPlayer();
      setState(() { _isPlaying = false; });
      
      if (_recordingPath == recording.path) {
        return; // If the same recording was playing, just stop it
      }
    }
    
    try {
      setState(() { 
        _recordingPath = recording.path;
      });
      
      await _playerController.preparePlayer(path: recording.path);
      await _playerController.startPlayer();
      
      setState(() { _isPlaying = true; });
      
      // Add listener for completion
      _playerController.onCompletion.listen((_) {
        if (mounted) {
          setState(() { _isPlaying = false; });
        }
      });
    } catch (e) {
      debugPrint('Error playing pinned recording: $e');
      setState(() { _isPlaying = false; });
    }
  }

  Future<void> _stopPlayback() async {
    if (!_isPlaying) return;
    
    await _playerController.stopPlayer();
    
    setState(() {
      _isPlaying = false;
    });
  }

  Future<bool> _showDeleteConfirmationDialog() async {
    return await showDialog<bool>(
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
                const Text(
                  'Your recording will be permanently deleted.\nThis action can\'t be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
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
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      _currentPosition = position;
      debugPrint('Current location: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _navigateToMap(BuildContext context) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MapView(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    
    // If a recording path is returned, play that recording
    if (result != null && result is String) {
      setState(() {
        _recordingPath = result;
      });
      
      try {
        await _playerController.preparePlayer(path: result);
        await _playerController.startPlayer();
        
        setState(() { _isPlaying = true; });
        
        // Add listener for completion
        _playerController.onCompletion.listen((_) {
          if (mounted) {
            setState(() { _isPlaying = false; });
          }
        });
      } catch (e) {
        debugPrint('Error playing recording from map: $e');
        setState(() { _isPlaying = false; });
      }
    }
  }

  void _navigateToRecordings(BuildContext context) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const RecordingsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);
          return SlideTransition(position: offsetAnimation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
    
    // Reload pinned recordings when coming back from recordings screen
    _loadPinnedRecordings();
  }

  @override
  void dispose() {
    _recorderController.dispose();
    _playerController.dispose();
    _timer?.cancel();
    _recordingNameController.dispose();
    _animController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('rekoda'),
        backgroundColor: Colors.red,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map, color: Colors.white),
            onPressed: () => _navigateToMap(context),
            tooltip: 'View Recording Locations',
          ),
          IconButton(
            icon: const Icon(Icons.list, color: Colors.white),
            onPressed: () => _navigateToRecordings(context),
            tooltip: 'My Recordings',
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! < 0) {
            // Swiping from right to left - open recordings screen
            _navigateToRecordings(context);
          }
        },
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Main content area with waveform or pinned recordings
              Expanded(
                child: _buildContentArea(),
              ),
              
              // Timer at the bottom during recording
              if (_isRecording)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatDuration(_recordingDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Control buttons at the bottom
              Padding(
                padding: const EdgeInsets.only(bottom: 50.0),
                child: _buildControlButtons(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentArea() {
    if (!_recorderIsReady) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    
    if (_isRecording) {
      // Show waveform during recording
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: AudioWaveforms(
            size: Size(MediaQuery.of(context).size.width - 40, 200),
            recorderController: _recorderController,
            waveStyle: const WaveStyle(
              waveColor: Colors.red,
              extendWaveform: true,
              showMiddleLine: false,
              spacing: 5.0,
              waveThickness: 3.0,
              scaleFactor: 200.0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.0),
              color: Colors.transparent,
            ),
            padding: const EdgeInsets.all(0),
          ),
        ),
      );
    } else if (_isPlaying) {
      // Show waveform during playback
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Now Playing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: AudioFileWaveforms(
                  size: Size(MediaQuery.of(context).size.width - 40, 200),
                  playerController: _playerController,
                  enableSeekGesture: true,
                  // density: 1.5,
                  playerWaveStyle: const PlayerWaveStyle(
                    // waveColor: Colors.blue,
                    seekLineColor: Colors.red,
                    showSeekLine: true,
                    spacing: 5.0,
                    waveThickness: 3.0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Colors.transparent,
                  ),
                  padding: const EdgeInsets.all(0),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Show pinned recordings when not recording or playing
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text(
              'Pinned Recordings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: _pinnedRecordings.isEmpty
                ? const Center(
                    child: Text(
                      'No pinned recordings yet.\nLong-press a recording to pin it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _pinnedRecordings.length,
                    itemBuilder: (context, index) {
                      final recording = _pinnedRecordings[index];
                      final dayMonth = DateFormat('d MMM').format(recording.date);
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
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
                          onTap: () => _playPinnedRecording(recording),
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
                                    IconButton(
                                      icon: Icon(
                                        (_isPlaying && _recordingPath == recording.path) 
                                            ? Icons.pause 
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                      ),
                                      onPressed: () => _playPinnedRecording(recording),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  dayMonth,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Delete button (only visible when recording)
        if (_isRecording)
          TextButton(
            onPressed: _handleDeleteRecording,
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          )
        else
          const SizedBox(width: 80), // Placeholder to keep layout balanced
        
        // Main recording button
        Container(
          width: 80, // Made slightly bigger
          height: 80, // Made slightly bigger
          decoration: BoxDecoration(
            color: _isRecording ? Colors.red : Colors.red, // Changed to red
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.3),
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: _handleMainButtonPress,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: _isRecording
                    ? (_isPaused
                        ? const Icon(Icons.play_arrow, color: Colors.white, size: 36, key: ValueKey('play'))
                        : const Icon(Icons.pause, color: Colors.white, size: 36, key: ValueKey('pause')))
                    : const Icon(Icons.mic, color: Colors.white, size: 36, key: ValueKey('mic')),
                ),
              ),
            ),
          ),
        ),
        
        // Save button (only visible when recording)
        if (_isRecording)
          TextButton(
            onPressed: _stopRecording,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          )
        else
          const SizedBox(width: 80), // Placeholder to keep layout balanced
      ],
    );
  }

  void _handleMainButtonPress() {
    if (_isPlaying) {
      _stopPlayback();
    } else if (_isRecording) {
      if (_isPaused) {
        _resumeRecording();
      } else {
        _pauseRecording();
      }
    } else {
      _startRecording();
    }
  }

  Future<void> _handleDeleteRecording() async {
    // Show confirmation dialog first
    bool confirmDelete = await _showDeleteConfirmationDialog();
    
    if (!confirmDelete) return;
    
    // Stop recording and delete
    await _recorderController.stop();
    await _deleteTempRecording();
    
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
    _resetTimer(); // Reset timer to 0 when deleting
  }
}