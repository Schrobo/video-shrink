import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_shrink/domain.dart';
import 'package:video_shrink/ffmpeg_service.dart';

void main() {
  final directories = [
    '/opt/homebrew/bin',
    '/usr/local/bin',
    ...(Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    ),
  ];
  final suffix = Platform.isWindows ? '.exe' : '';
  final tools = directories
      .where(
        (dir) =>
            File(p.join(dir, 'ffmpeg$suffix')).existsSync() &&
            File(p.join(dir, 'ffprobe$suffix')).existsSync(),
      )
      .firstOrNull;
  group(
    'real local FFmpeg integration',
    skip: tools == null
        ? 'FFmpeg/FFprobe fehlen in dieser Testumgebung.'
        : false,
    () {
      late Directory temp;
      late VideoProcessor processor;
      setUp(() async {
        temp = await Directory.systemTemp.createTemp('video-shrink-test-');
        processor = VideoProcessor(toolsDirectory: tools);
      });
      tearDown(() async {
        processor.cancel();
        await temp.delete(recursive: true);
      });
      Future<String> fixture(
        String name, {
        String source = 'testsrc2=size=640x360:rate=30',
        bool audio = true,
        String codec = 'libx264',
        List<String> extra = const [],
      }) async {
        final path = p.join(temp.path, name);
        final result = await Process.run(p.join(tools!, 'ffmpeg$suffix'), [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          source,
          if (audio) ...[
            '-f',
            'lavfi',
            '-i',
            'sine=frequency=440:sample_rate=48000',
          ],
          '-t',
          '3',
          '-c:v',
          codec,
          if (codec == 'libx264') ...['-preset', 'ultrafast', '-crf', '12'],
          if (audio) ...['-c:a', 'aac'],
          ...extra,
          '-n',
          path,
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return path;
      }

      Future<ConversionResult> convert(String path) async {
        final video = await processor.analyze(path);
        return processor.convert(
          video,
          CompressionPlan.recommend(
            video,
            VideoGoal.compact,
            VideoContent.everyday,
          ),
          (_, _) {},
        );
      }

      test(
        'a real clip preserves its source and never overwrites an existing output',
        () async {
          final source = await fixture('clip with spaces ü.mp4');
          final before = await File(source).readAsBytes();
          final collision = File(
            p.join(temp.path, 'clip with spaces ü-whatsapp.mp4'),
          );
          await collision.writeAsString('existing file');
          final result = await convert(source);
          expect(result.path, endsWith('-whatsapp-1.mp4'));
          expect(result.bytes, lessThanOrEqualTo(VideoGoal.compact.maxBytes));
          expect(await File(source).readAsBytes(), before);
          expect(await collision.readAsString(), 'existing file');
          final info = await processor.analyze(result.path);
          expect(info.hasAudio, isTrue);
          expect(info.duration, closeTo(3, .1));
          expect(
            await temp
                .list()
                .where(
                  (entry) =>
                      p.basename(entry.path).startsWith('.video-shrink-'),
                )
                .isEmpty,
            isTrue,
          );
        },
      );
      test(
        'odd dimensions without audio become even without adding audio',
        () async {
          final source = await fixture(
            'silent odd.mkv',
            source: 'testsrc=size=321x181:rate=24',
            audio: false,
            codec: 'ffv1',
          );
          final result = await convert(source);
          final info = await processor.analyze(result.path);
          expect(info.width, 320);
          expect(info.height, 180);
          expect(info.hasAudio, isFalse);
          expect(info.fps, 24);
        },
      );
      test('rotation metadata results in an upright portrait output', () async {
        final source = await fixture('landscape.mp4');
        final rotated = p.join(temp.path, 'rotated.mov');
        final result = await Process.run(p.join(tools!, 'ffmpeg$suffix'), [
          '-v',
          'error',
          '-display_rotation',
          '90',
          '-i',
          source,
          '-c',
          'copy',
          '-n',
          rotated,
        ]);
        expect(result.exitCode, 0);
        final converted = await convert(rotated);
        final info = await processor.analyze(converted.path);
        expect(info.height, greaterThan(info.width));
        expect(info.rotation, 0);
      });
      test('HDR input is explicitly converted to SDR', () async {
        final source = await fixture(
          'hdr.mp4',
          audio: false,
          extra: [
            '-vf',
            'format=yuv420p10le,setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc',
          ],
        );
        expect((await processor.analyze(source)).hdr, isTrue);
        final filters = await Process.run(p.join(tools!, 'ffmpeg$suffix'), [
          '-hide_banner',
          '-filters',
        ]);
        if (!RegExp(r'\bzscale\b').hasMatch(filters.stdout.toString())) {
          await expectLater(
            convert(source),
            throwsA(
              isA<VideoException>().having(
                (e) => e.message,
                'message',
                contains('HDR'),
              ),
            ),
          );
          expect(await File(source).exists(), isTrue);
          return;
        }
        final converted = await convert(source);
        expect((await processor.analyze(converted.path)).hdr, isFalse);
      });
      test('cancel leaves the source intact and publishes no output', () async {
        final source = await fixture('cancel.mp4');
        final video = await processor.analyze(source);
        final plan = CompressionPlan.recommend(
          video,
          VideoGoal.compact,
          VideoContent.everyday,
        );
        await expectLater(
          processor.convert(video, plan, (_, phase) {
            if (phase == 'Video verkleinern') processor.cancel();
          }),
          throwsA(isA<VideoException>()),
        );
        expect(await File(source).exists(), isTrue);
        expect(await temp.list().length, 1);
        // The same processor remains usable after cancellation.
        expect((await processor.analyze(source)).duration, closeTo(3, .1));
      });
      test('audio-only and broken files produce actionable errors', () async {
        final audio = p.join(temp.path, 'audio.wav');
        await Process.run(p.join(tools!, 'ffmpeg$suffix'), [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440',
          '-t',
          '1',
          audio,
        ]);
        await expectLater(
          processor.analyze(audio),
          throwsA(isA<VideoException>()),
        );
        final broken = File(p.join(temp.path, 'broken.mp4'));
        await broken.writeAsBytes(utf8.encode('not a video'));
        await expectLater(
          processor.analyze(broken.path),
          throwsA(isA<VideoException>()),
        );
      });
    },
  );
}
