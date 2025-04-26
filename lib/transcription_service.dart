import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class TranscriptionService {
  late SpeechToText _speechToText;
  bool _speechEnabled = false;
  String _transcription = '';
  double _confidence = 1.0;
  final Function(String, double) _onTranscriptionUpdate;

  TranscriptionService({required Function(String, double) onTranscriptionUpdate})
      : _onTranscriptionUpdate = onTranscriptionUpdate {
    _speechToText = SpeechToText();
  }

  String get transcription => _transcription;
  double get confidence => _confidence;
  bool get isListening => _speechToText.isListening;
  bool get isAvailable => _speechEnabled;

  Future<void> initialize() async {
    debugPrint('Initializing speech recognition with MINIMAL settings...');
    try {
      // Always create a new instance to avoid any lingering issues
      _speechToText = SpeechToText();
      
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          debugPrint('Speech recognition error: ${error.errorMsg}');
          // Only notify UI of critical errors, not timeouts
          if (error.errorMsg != 'error_speech_timeout') {
            _onTranscriptionUpdate('Error: ${error.errorMsg}', 0.0);
          }
        },
        onStatus: (status) {
          debugPrint('Speech recognition status: $status');
        },
        debugLogging: true,
      );
      
      debugPrint('Speech recognition initialized: $_speechEnabled');
      
      if (_speechEnabled) {
        try {
          // Only log a few locales to reduce log clutter
          final locales = await _speechToText.locales();
          final enLocales = locales.where((l) => l.localeId.startsWith('en_')).toList();
          debugPrint('English locales: ${enLocales.map((l) => l.localeId).join(', ')}');
        } catch (e) {
          debugPrint('Error getting locales: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to initialize speech recognition: $e');
      _speechEnabled = false;
    }
  }

  Future<bool> startListening() async {
    if (!_speechEnabled) {
      debugPrint('Speech recognition not available');
      return false;
    }

    try {
      // Stop any existing session
      if (_speechToText.isListening) {
        await _speechToText.stop();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // Clear previous transcription and update UI
      _transcription = '';
      _onTranscriptionUpdate('Listening...', 1.0);
      
      // Use the MOST BASIC configuration - don't overcomplicate
      bool started = await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 30), // Much shorter duration
        partialResults: true,
        localeId: 'en_US',
        listenMode: ListenMode.confirmation, // Use confirmation mode instead of dictation
      );
      
      debugPrint('Speech recognition started: $started');
      return started;
    } catch (e) {
      debugPrint('Error starting speech recognition: $e');
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      if (_speechToText.isListening) {
        await _speechToText.stop();
        debugPrint('Speech recognition stopped');
      }
    } catch (e) {
      debugPrint('Error stopping speech recognition: $e');
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    debugPrint('Recognition result: "${result.recognizedWords}" (final: ${result.finalResult})');
    
    // Only update if we actually got words
    if (result.recognizedWords.isNotEmpty) {
      _transcription = result.recognizedWords;
      
      // Update confidence
      if (result.hasConfidenceRating && result.confidence > 0) {
        _confidence = result.confidence;
      }
      
      // IMPORTANT: Update the UI with the new transcription
      _onTranscriptionUpdate(_transcription, _confidence);
      
      debugPrint('Updated transcription to: "$_transcription" with confidence: ${_confidence.toStringAsFixed(2)}');
    } else {
      debugPrint('Received empty transcription, not updating UI');
    }
  }

  void dispose() {
    stopListening();
    debugPrint('TranscriptionService disposed');
  }
}