import 'dart:io';
import 'package:path/path.dart' as p;

/// Bundles an explicitly supplied, redistributable FFmpeg directory. No downloads.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Verwendung: dart run tool/bundle_ffmpeg.dart <FFmpeg-Verzeichnis> <Zielverzeichnis>',
    );
    exitCode = 2;
    return;
  }
  final source = Directory(p.absolute(args[0]));
  final destination = Directory(p.absolute(args[1]));
  final suffix = Platform.isWindows ? '.exe' : '';
  try {
    for (final name in [
      'ffmpeg$suffix',
      'ffprobe$suffix',
      'LICENSE.txt',
      'SOURCES.txt',
    ]) {
      if (!await File(p.join(source.path, name)).exists()) {
        throw Exception('Im Quellverzeichnis fehlt $name.');
      }
    }
    final encoders = await Process.run(p.join(source.path, 'ffmpeg$suffix'), [
      '-hide_banner',
      '-encoders',
    ]);
    final filters = await Process.run(p.join(source.path, 'ffmpeg$suffix'), [
      '-hide_banner',
      '-filters',
    ]);
    if (encoders.exitCode != 0 ||
        filters.exitCode != 0 ||
        !RegExp(r'\blibx264\b').hasMatch(encoders.stdout.toString()) ||
        !RegExp(r'\baac\b').hasMatch(encoders.stdout.toString()) ||
        !RegExp(r'\bzscale\b').hasMatch(filters.stdout.toString()) ||
        !RegExp(r'\btonemap\b').hasMatch(filters.stdout.toString())) {
      throw Exception(
        'Das FFmpeg-Paket benötigt libx264, AAC, zscale und tonemap.',
      );
    }
    if (await destination.exists()) {
      throw Exception(
        'Das Zielverzeichnis existiert bereits. Es wird nicht überschrieben.',
      );
    }
    for (final entry
        in await source.list(recursive: true, followLinks: false).toList()) {
      if (entry is Link) {
        throw Exception(
          'Verwende ein eigenständiges Paket ohne symbolische Links.',
        );
      }
    }
    await destination.create(recursive: true);
    await for (final entry in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final target = p.join(
        destination.path,
        p.relative(entry.path, from: source.path),
      );
      if (entry is Directory) {
        await Directory(target).create(recursive: true);
      }
      if (entry is File) {
        await Directory(p.dirname(target)).create(recursive: true);
        await entry.copy(target);
      }
    }
    if (!Platform.isWindows) {
      for (final name in ['ffmpeg', 'ffprobe']) {
        final result = await Process.run('chmod', [
          'u+x',
          p.join(destination.path, name),
        ]);
        if (result.exitCode != 0) {
          throw Exception('Ausführungsrechte konnten nicht gesetzt werden.');
        }
      }
    }
    final version = await Process.run(
      p.join(destination.path, 'ffprobe$suffix'),
      ['-version'],
    );
    if (version.exitCode != 0) {
      throw Exception(
        'FFprobe lässt sich aus dem kopierten Paket nicht starten.',
      );
    }
    stdout.writeln(
      'FFmpeg-Paket kopiert. Signierung und Prüfung auf einem Rechner ohne FFmpeg sind vor der Verteilung erforderlich.',
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
