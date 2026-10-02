import 'domain.dart';
import 'dart:io';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'ffmpeg_service.dart';

class VideoBackend {
  final processor = VideoProcessor();
  String? outputDirectory;
  bool get isPreview => false;
  Future<String?> pickVideo() async =>
      (await FileSelectorPlatform.instance.openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Videos',
            extensions: [
              'mp4',
              'mov',
              'mkv',
              'avi',
              'webm',
              'm4v',
              'mts',
              'm2ts',
              '3gp',
              'flv',
            ],
            uniformTypeIdentifiers: ['public.movie'],
          ),
        ],
      ))?.path;
  Future<VideoInfo> analyze(String path) => processor.analyze(path);
  Future<ConversionResult> convert(
    VideoInfo video,
    CompressionPlan plan,
    void Function(double, String) onProgress,
  ) async {
    // A selected file grants access to that file. macOS needs an explicit
    // directory selection to write a sibling file while keeping App Sandbox.
    if (Platform.isMacOS && outputDirectory == null) {
      outputDirectory = await FileSelectorPlatform.instance.getDirectoryPath(
        initialDirectory: p.dirname(video.path),
        confirmButtonText: 'Hier speichern',
      );
      if (outputDirectory == null) {
        throw const VideoException(
          'Speichern abgebrochen. Wähle einen Ausgabeordner und starte erneut.',
        );
      }
    }
    return processor.convert(
      video,
      plan,
      onProgress,
      outputDirectory: outputDirectory,
    );
  }

  Future<void> chooseOutputDirectory() async {
    final directory = await FileSelectorPlatform.instance.getDirectoryPath(
      confirmButtonText: 'Hier speichern',
    );
    if (directory != null) outputDirectory = directory;
  }

  void cancel() => processor.cancel();
  Future<void> reveal(String path) => _launch(
    Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'explorer.exe'
        : 'xdg-open',
    Platform.isMacOS
        ? ['-R', path]
        : Platform.isWindows
        ? ['/select,', path]
        : [p.dirname(path)],
  );
  Future<void> open(String path) => _launch(
    Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'explorer.exe'
        : 'xdg-open',
    [path],
  );
  Future<void> _launch(String command, List<String> args) async {
    final result = await Process.run(command, args, runInShell: false);
    if (result.exitCode != 0) {
      throw const VideoException('Die Datei konnte nicht geöffnet werden.');
    }
  }
}
