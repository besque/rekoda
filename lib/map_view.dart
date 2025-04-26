import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'dart:io';
import 'dart:convert';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class RecordingPin {
  final String id;
  final String name;
  final String path;
  final LatLng point;
  final String transcription;
  final double confidence;

  const RecordingPin({
    required this.id,
    required this.name,
    required this.path,
    required this.point,
    this.transcription = '',
    this.confidence = 1.0,
  });
}

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<RecordingPin> _recordingPins = [];
  late MapController _mapController;
  late PlayerController _playerController;
  LatLng? _currentLocation;
  bool _fitAll = true;
  LatLngBounds? _bounds;
  
  // Animation controller for markers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Playback state
  bool _isPlaying = false;
  String? _currentPlayingPath;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _playerController = PlayerController();
    
    // Initialize pulse animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _loadRecordingsWithLocation();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _loadRecordingsWithLocation() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${appDir.path}/recordings');

      if (!await recordingsDir.exists()) {
        setState(() {
          _loading = false;
        });
        return;
      }

      final List<RecordingPin> pins = [];

      final List<FileSystemEntity> files = await recordingsDir.list().toList();
      for (var file in files) {
        if (file.path.endsWith('.json')) {
          final String jsonContent = await File(file.path).readAsString();
          final Map<String, dynamic> recordingData = json.decode(jsonContent);

          final latitude = recordingData['latitude'];
          final longitude = recordingData['longitude'];

          if (latitude != null && longitude != null) {
            pins.add(
              RecordingPin(
                id:
                    recordingData['id'] ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                name: recordingData['name'] ?? 'Unknown Recording',
                path: recordingData['path'] ?? '',
                point: LatLng(
                  (latitude as num).toDouble(),
                  (longitude as num).toDouble(),
                ),
                transcription: recordingData['transcription'] ?? '',
                confidence: (recordingData['confidence'] ?? 1.0) as double,
              ),
            );
          }
        }
      }

      if (pins.isNotEmpty) {
        setState(() {
          _recordingPins = pins;
          _bounds = _calculateBounds(pins.map((pin) => pin.point).toList());
        });
      }
    } catch (e) {
      debugPrint('Error loading recordings with location: $e');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  LatLngBounds? _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) return null;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  void _toggleMapView() {
    if (_fitAll && _currentLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(_currentLocation!, 15.0);
      });
    } else if (_bounds != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.fitBounds(
          _bounds!,
          options: const FitBoundsOptions(padding: EdgeInsets.all(50.0)),
        );
      });
    }

    setState(() {
      _fitAll = !_fitAll;
    });
  }

  // New method to play recording with waveform visualization
  Future<void> _playRecordingWithWaveform(RecordingPin pin) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                
                // Recording info
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pin.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${pin.point.latitude.toStringAsFixed(4)}, ${pin.point.longitude.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Waveform visualization
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
                        color: Colors.black12,
                      ),
                      padding: const EdgeInsets.all(0),
                    ),
                  ),
                ),
                
                // Playback controls
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          color: Colors.white,
                          size: 64,
                        ),
                        onPressed: () async {
                          if (_isPlaying) {
                            await _playerController.pausePlayer();
                            setModalState(() {
                              _isPlaying = false;
                            });
                          } else {
                            if (_currentPlayingPath == pin.path) {
                              await _playerController.startPlayer();
                            } else {
                              _currentPlayingPath = pin.path;
                              await _playerController.preparePlayer(path: pin.path);
                              await _playerController.startPlayer();
                              
                              // Listen for completion
                              _playerController.onCompletion.listen((_) {
                                setModalState(() {
                                  _isPlaying = false;
                                });
                              });
                            }
                            setModalState(() {
                              _isPlaying = true;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() async {
      // Stop player when modal is closed and update state
      if (_isPlaying) {
        await _playerController.stopPlayer();
        setState(() {
          _isPlaying = false;
        });
      }
    });
  }

  // Play recording with waveform instead of returning to home screen
  void _playRecording(RecordingPin pin) {
    _playRecordingWithWaveform(pin);
  }

  @override
  void dispose() {
    _playerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LatLng defaultCenter = const LatLng(0, 0);
    final LatLng center =
        _currentLocation ??
        (_bounds != null
            ? LatLng(
              (_bounds!.south + _bounds!.north) / 2,
              (_bounds!.west + _bounds!.east) / 2,
            )
            : defaultCenter);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Recording Locations'),
        backgroundColor: Colors.red,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        actions: [
          IconButton(
            icon: Icon(_fitAll ? Icons.gps_fixed : Icons.map, color: Colors.white),
            onPressed: _toggleMapView,
            tooltip:
                _fitAll ? 'Focus on current location' : 'Show all recordings',
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : (_recordingPins.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No recordings with location data',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Make sure location permissions are enabled',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF757575),
                          ),
                        ),
                      ],
                    ),
                  )
                  : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                      ),
                      if (_currentLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentLocation!,
                              width: 40,
                              height: 40,
                              child: AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: 1.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.7),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue.withOpacity(0.5 * _pulseAnimation.value),
                                            spreadRadius: 10 * _pulseAnimation.value,
                                            blurRadius: 10 * _pulseAnimation.value,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.my_location,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers:
                            _recordingPins
                                .map<Marker>(
                                  (pin) => Marker(
                                    point: pin.point,
                                    width: 50.0,
                                    height: 50.0,
                                    child: AnimatedBuilder(
                                      animation: _pulseAnimation,
                                      builder: (context, child) {
                                        return Transform.scale(
                                          scale: _pulseAnimation.value,
                                          child: GestureDetector(
                                            onTap: () => _playRecording(pin),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.5),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.location_on,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ],
                  )),
    );
  }
}