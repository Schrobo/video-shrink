import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'domain.dart';

class VideoBackend {
  bool _cancelled = false;
  bool get isPreview => true;
  String? get outputDirectory => null;
  Future<void> chooseOutputDirectory() async {}
  Future<String?> pickVideo() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'video/*,.mkv,.avi';
    final completer = Completer<String?>();
    input.addEventListener(
      'change',
      ((web.Event _) {
        completer.complete(input.files?.item(0)?.name);
      }).toJS,
    );
    input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!completer.isCompleted) completer.complete(null);
      }).toJS,
    );
    input.click();
    return completer.future;
  }

  Future<VideoInfo> analyze(String path) async {
    final name = path.split('/').last;
    if (!RegExp(
      r'\.(mp4|mov|mkv|avi|webm|m4v|mts|m2ts|3gp|flv)$',
      caseSensitive: false,
    ).hasMatch(name)) {
      throw const VideoException('Wähle für die Vorschau eine Videodatei aus.');
    }
    return exampleVideo(name: name);
  }

  Future<ConversionResult> convert(
    VideoInfo video,
    CompressionPlan plan,
    void Function(double, String) onProgress,
  ) async {
    _cancelled = false;
    for (var i = 0; i <= 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_cancelled) {
        throw const VideoException(
          'Abgebrochen. Du kannst ein neues Video auswählen.',
        );
      }
      onProgress(i / 40, i == 40 ? 'Ausgabe prüfen' : 'Video verkleinern');
    }
    return const ConversionResult('', 5100000, simulated: true);
  }

  void cancel() => _cancelled = true;
  Future<void> reveal(String path) async {}
  Future<void> open(String path) async {}
}
