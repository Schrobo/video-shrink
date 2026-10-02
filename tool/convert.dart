import 'dart:io';
import 'package:video_shrink/domain.dart';
import 'package:video_shrink/ffmpeg_service.dart';

/// Uses the exact desktop adapter without a Flutter window.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Verwendung: dart run tool/convert.dart <Video> [--quality|--text]',
    );
    exitCode = 2;
    return;
  }
  final processor = VideoProcessor();
  final interrupt = ProcessSignal.sigint.watch().listen(
    (_) => processor.cancel(),
  );
  try {
    final video = await processor.analyze(args.first);
    final plan = CompressionPlan.recommend(
      video,
      args.contains('--quality') ? VideoGoal.quality : VideoGoal.compact,
      args.contains('--text') ? VideoContent.text : VideoContent.everyday,
    );
    stdout.writeln(
      'Empfehlung: ${plan.resolution}, ${plan.fps} fps, bis ${formatBytes(plan.goal.maxBytes)}',
    );
    var lastPhase = '';
    final result = await processor.convert(video, plan, (_, phase) {
      if (phase != lastPhase) {
        stdout.writeln(phase);
        lastPhase = phase;
      }
    });
    stdout.writeln(
      '${formatBytes(video.bytes)} → ${formatBytes(result.bytes)}',
    );
    stdout.writeln(result.path);
  } on VideoException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } finally {
    await interrupt.cancel();
  }
}
