import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'domain.dart';

/// Local-only process adapter. Paths are arguments, never shell commands.
class VideoProcessor {
  final String? toolsDirectory;
  VideoProcessor({this.toolsDirectory});
  final Set<Process> _processes = {};
  bool _cancelled = false, _busy = false;
  String? _ffmpeg, _ffprobe;

  Future<T> _session<T>(Future<T> Function() action) async {
    if (_busy) {
      throw const VideoException('Es wird bereits ein Video verarbeitet.');
    }
    _busy = true;
    _cancelled = false;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  void cancel() {
    _cancelled = true;
    for (final process in _processes.toList()) {
      process.kill();
    }
  }

  void _checkCancellation() {
    if (_cancelled) {
      throw const VideoException('Abgebrochen. Das Original bleibt erhalten.');
    }
  }

  Future<void> _resolveTools() async {
    if (_ffmpeg != null && _ffprobe != null) return;
    final exe = p.dirname(Platform.resolvedExecutable);
    final explicit =
        toolsDirectory ?? Platform.environment['VIDEO_SHRINK_FFMPEG_DIR'];
    final directories = <String>[
      ?explicit,
      p.join(exe, '..', 'Resources', 'ffmpeg'), // macOS bundle
      p.join(exe, 'ffmpeg'),
      p.join(exe, 'lib', 'ffmpeg'), // Windows/Linux bundle
      if (explicit == null && Platform.isMacOS) ...[
        '/opt/homebrew/bin',
        '/usr/local/bin',
      ],
      if (explicit == null)
        ...(Platform.environment['PATH'] ?? '').split(
          Platform.isWindows ? ';' : ':',
        ),
    ];
    for (final dir in explicit == null ? directories : [explicit]) {
      if (dir.isEmpty) continue;
      final suffix = Platform.isWindows ? '.exe' : '';
      final ffmpeg = p.join(dir, 'ffmpeg$suffix'),
          ffprobe = p.join(dir, 'ffprobe$suffix');
      if (await File(ffmpeg).exists() && await File(ffprobe).exists()) {
        _ffmpeg = ffmpeg;
        _ffprobe = ffprobe;
        return;
      }
    }
    throw const VideoException(
      'FFmpeg und FFprobe fehlen. Verwende ein App-Paket mit den mitgelieferten Videowerkzeugen.',
    );
  }

  Future<String> _run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    void Function(String line)? onLine,
  }) async {
    _checkCancellation();
    Process process;
    try {
      process = await Process.start(executable, arguments, runInShell: false);
    } on ProcessException {
      throw const VideoException(
        'Das Videowerkzeug konnte nicht gestartet werden. Prüfe das App-Paket.',
      );
    }
    _processes.add(process);
    if (_cancelled) process.kill();
    var timedOut = false;
    final timer = timeout == null
        ? null
        : Timer(timeout, () {
            timedOut = true;
            process.kill();
          });
    final output = StringBuffer();
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (onLine != null) {
            onLine(line);
          } else if (output.length < 1000000) {
            output.writeln(line);
          }
        });
    // Drain stderr without leaking filenames, metadata or raw process diagnostics.
    final stderrDone = process.stderr.drain<void>();
    try {
      final exit = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      _checkCancellation();
      if (timedOut) {
        throw const VideoException(
          'Die Analyse dauert zu lange. Prüfe, ob die Datei vollständig lokal verfügbar ist.',
        );
      }
      if (exit != 0) {
        throw const VideoException(
          'Die Verarbeitung ist fehlgeschlagen. Prüfe die Datei, den freien Speicher und die Schreibrechte.',
        );
      }
      return output.toString();
    } finally {
      timer?.cancel();
      _processes.remove(process);
    }
  }

  Future<Map<String, dynamic>> _probe(String path) async {
    final output = await _run(_ffprobe!, [
      '-v',
      'error',
      '-protocol_whitelist',
      'file,pipe',
      '-format_whitelist',
      localVideoFormats,
      '-show_entries',
      'format=duration,format_name:stream=codec_type,codec_name,width,height,duration,avg_frame_rate,r_frame_rate,sample_aspect_ratio,color_transfer,pix_fmt:stream_disposition=attached_pic:stream_tags=rotate:stream_side_data=rotation',
      '-of',
      'json',
      '-i',
      path,
    ], timeout: const Duration(seconds: 45));
    try {
      return jsonDecode(output) as Map<String, dynamic>;
    } on FormatException {
      throw const VideoException(
        'Die Videodaten konnten nicht gelesen werden. Wähle eine andere Datei.',
      );
    }
  }

  Future<VideoInfo> analyze(String path) => _session(() async {
    final file = File(p.absolute(path));
    if (!await file.exists()) {
      throw const VideoException(
        'Die Datei ist nicht verfügbar. Lade sie lokal herunter und wähle sie erneut aus.',
      );
    }
    final bytes = await file.length();
    if (bytes == 0) {
      throw const VideoException(
        'Die Datei ist leer. Wähle eine andere Videodatei.',
      );
    }
    await _resolveTools();
    _checkCancellation();
    return VideoInfo.fromProbe(
      await _probe(file.path),
      path: file.path,
      name: p.basename(file.path),
      bytes: bytes,
    );
  });

  Future<void> _checkCapabilities(bool hdr) async {
    final encoders = await _run(_ffmpeg!, [
      '-hide_banner',
      '-encoders',
    ], timeout: const Duration(seconds: 10));
    if (!RegExp(r'\blibx264\b').hasMatch(encoders) ||
        !RegExp(r'\baac\b').hasMatch(encoders)) {
      throw const VideoException(
        'Dieses FFmpeg-Paket unterstützt H.264 oder AAC nicht. Verwende das vollständige App-Paket.',
      );
    }
    if (hdr) {
      final filters = await _run(_ffmpeg!, [
        '-hide_banner',
        '-filters',
      ], timeout: const Duration(seconds: 10));
      if (!RegExp(r'\bzscale\b').hasMatch(filters) ||
          !RegExp(r'\btonemap\b').hasMatch(filters)) {
        throw const VideoException(
          'Für dieses HDR-Video fehlen die Farbfilter im FFmpeg-Paket. Verwende das vollständige App-Paket.',
        );
      }
    }
  }

  Future<ConversionResult> convert(
    VideoInfo video,
    CompressionPlan plan,
    void Function(double, String) onProgress, {
    String? outputDirectory,
  }) => _session(() async {
    if (plan.needsLargerBudget) {
      throw VideoException(plan.warning ?? 'Wähle ein größeres Größenlimit.');
    }
    await _resolveTools();
    await _checkCapabilities(video.hdr);
    _checkCancellation();
    final directory = outputDirectory ?? p.dirname(video.path);
    // Private temporary directory in the output folder; never overwrite user files.
    Directory? work;
    try {
      work = await Directory(directory).createTemp('.video-shrink-');
      final output = p.join(work.path, 'video.mp4');
      for (var attempt = 0; attempt < 3; attempt++) {
        _checkCancellation();
        final attemptFile = p.join(work.path, 'attempt-$attempt.mp4');
        final factor = math.pow(.78, attempt).toDouble();
        onProgress(
          0,
          attempt == 0
              ? 'Video verkleinern'
              : 'Dateigröße nachbessern · Durchlauf ${attempt + 1}',
        );
        await _run(
          _ffmpeg!,
          plan.arguments(video, attemptFile, bitrateFactor: factor),
          onLine: (line) {
            if (line.startsWith('out_time_us=')) {
              final time = int.tryParse(line.substring('out_time_us='.length));
              if (time != null) {
                onProgress(
                  (time / 1000000 / video.duration * .94).clamp(0, .94),
                  attempt == 0
                      ? 'Video verkleinern'
                      : 'Dateigröße nachbessern · Durchlauf ${attempt + 1}',
                );
              }
            }
          },
        );
        _checkCancellation();
        final bytes = await File(attemptFile).length();
        if (bytes <= 0 || bytes > plan.goal.maxBytes) {
          continue;
        }
        onProgress(.95, 'Ausgabe prüfen');
        final probe = await _probe(attemptFile);
        final info = VideoInfo.fromProbe(
          probe,
          path: attemptFile,
          name: 'video.mp4',
          bytes: bytes,
        );
        final streams = (probe['streams'] as List).cast<Map<String, dynamic>>();
        final stream = streams.firstWhere((s) => s['codec_type'] == 'video');
        final audio = streams
            .where((s) => s['codec_type'] == 'audio')
            .firstOrNull;
        if (stream['codec_name'] != 'h264' ||
            stream['pix_fmt'] != 'yuv420p' ||
            info.width != plan.width ||
            info.height != plan.height ||
            (info.duration - video.duration).abs() >
                math.max(1, 2 / plan.fps) ||
            (video.hasAudio && audio?['codec_name'] != 'aac')) {
          throw const VideoException(
            'Die Ausgabeprüfung ist fehlgeschlagen. Das Original bleibt erhalten.',
          );
        }
        // Decode the complete output before exposing it as a finished result.
        await _run(_ffmpeg!, [
          '-v',
          'error',
          '-xerror',
          '-nostdin',
          '-i',
          attemptFile,
          '-f',
          'null',
          '-',
        ]);
        _checkCancellation();
        if (bytes >= video.bytes && video.bytes <= plan.goal.maxBytes) {
          final sourceProbe = await _probe(video.path);
          final sourceStreams = (sourceProbe['streams'] as List)
              .cast<Map<String, dynamic>>();
          final sourceVideo = sourceStreams
              .where(
                (s) =>
                    s['codec_type'] == 'video' &&
                    (s['disposition']?['attached_pic'] ?? 0) != 1,
              )
              .firstOrNull;
          final sourceAudio = sourceStreams
              .where((s) => s['codec_type'] == 'audio')
              .firstOrNull;
          if (p.extension(video.path).toLowerCase() == '.mp4' &&
              !video.hdr &&
              sourceVideo?['codec_name'] == 'h264' &&
              sourceVideo?['pix_fmt'] == 'yuv420p' &&
              (!video.hasAudio || sourceAudio?['codec_name'] == 'aac')) {
            onProgress(1, 'Video passt bereits');
            return ConversionResult(video.path, video.bytes, unchanged: true);
          }
        }
        await File(attemptFile).rename(output);
        final finalPath = await _publishWithoutOverwrite(
          output,
          video.path,
          directory,
        );
        onProgress(1, 'Fertig');
        return ConversionResult(finalPath, bytes);
      }
      throw const VideoException(
        'Das Größenlimit wurde nicht erreicht. Wähle „Mehr Qualität“ oder ein kürzeres Video.',
      );
    } on FileSystemException {
      throw const VideoException(
        'Die Datei konnte nicht gespeichert werden. Prüfe Speicherplatz und Schreibrechte im Originalordner.',
      );
    } finally {
      // Only remove the temporary directory created by this conversion.
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  });

  Future<String> _publishWithoutOverwrite(
    String output,
    String source,
    String directory,
  ) async {
    final base = p.join(
      directory,
      '${p.basenameWithoutExtension(source)}-whatsapp',
    );
    // Reserve a new filename exclusively; never truncate an existing user file.
    for (var index = 0; index < 1000; index++) {
      _checkCancellation();
      final target = '$base${index == 0 ? '' : '-$index'}.mp4';
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      RandomAccessFile? destination;
      var reserved = false;
      try {
        await File(target).create(exclusive: true);
        reserved = true;
        destination = await File(target).open(mode: FileMode.writeOnly);
        final stream = File(output).openRead();
        await for (final chunk in stream) {
          _checkCancellation();
          await destination.writeFrom(chunk);
        }
        _checkCancellation();
        await destination.flush();
        await destination.close();
        destination = null;
        return target;
      } catch (_) {
        await destination?.close();
        if (reserved) {
          await File(target).delete();
          rethrow;
        }
        if (!_cancelled &&
            await FileSystemEntity.type(target, followLinks: false) !=
                FileSystemEntityType.notFound) {
          continue;
        }
        rethrow;
      }
    }
    throw const VideoException(
      'Es gibt bereits zu viele Ausgabedateien mit diesem Namen. Benenne das Original um.',
    );
  }
}
