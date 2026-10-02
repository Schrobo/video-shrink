import 'package:flutter_test/flutter_test.dart';
import 'package:video_shrink/domain.dart';

void main() {
  VideoInfo source({
    int width = 1920,
    int height = 1080,
    double seconds = 240,
    double fps = 30,
    bool audio = true,
    int rotation = 0,
    double sar = 1,
  }) => VideoInfo(
    path: '/local/video.mp4',
    name: 'video.mp4',
    bytes: 48000000,
    duration: seconds,
    width: width,
    height: height,
    fps: fps,
    hasAudio: audio,
    rotation: rotation,
    sampleAspectRatio: sar,
  );
  test(
    'recommendations preserve orientation, avoid upscaling and use even dimensions',
    () {
      for (final dimensions in [
        (1920, 1054),
        (2160, 3840),
        (320, 181),
        (4096, 2160),
        (720, 720),
      ]) {
        final video = source(
          width: dimensions.$1,
          height: dimensions.$2,
          seconds: 42,
          fps: 60,
        );
        final plan = CompressionPlan.recommend(
          video,
          VideoGoal.compact,
          VideoContent.everyday,
        );
        expect(plan.width, lessThanOrEqualTo(video.displayWidth));
        expect(plan.height, lessThanOrEqualTo(video.displayHeight));
        expect(plan.width.isEven && plan.height.isEven, isTrue);
        expect(
          plan.width / plan.height,
          closeTo(video.displayWidth / video.displayHeight, .025),
        );
        expect(plan.fps, 30);
      }
    },
  );
  test('rotation and anamorphic input affect the display geometry', () {
    final rotated = CompressionPlan.recommend(
      source(rotation: -90),
      VideoGoal.compact,
      VideoContent.everyday,
    );
    expect(rotated.height, greaterThan(rotated.width));
    final anamorphic = CompressionPlan.recommend(
      source(width: 720, height: 576, seconds: 20, sar: 16 / 15),
      VideoGoal.compact,
      VideoContent.everyday,
    );
    expect(anamorphic.width / anamorphic.height, closeTo(4 / 3, .01));
  });
  test(
    'long clips stop automatic encoding before quality becomes unusable',
    () {
      final small = CompressionPlan.recommend(
        source(seconds: 2400),
        VideoGoal.compact,
        VideoContent.everyday,
      );
      final large = CompressionPlan.recommend(
        source(seconds: 2400),
        VideoGoal.quality,
        VideoContent.everyday,
      );
      expect(small.needsLargerBudget, isTrue);
      expect(small.warning, isNotNull);
      expect(large.needsLargerBudget, isFalse);
    },
  );
  test('no-audio sources use the available bitrate for video', () {
    final withAudio = CompressionPlan.recommend(
      source(),
      VideoGoal.compact,
      VideoContent.everyday,
    );
    final silent = CompressionPlan.recommend(
      source(audio: false),
      VideoGoal.compact,
      VideoContent.everyday,
    );
    expect(silent.audioKbps, 0);
    expect(silent.videoKbps, greaterThan(withAudio.videoKbps));
  });
  test('probe ignores cover art and accepts valid fallback duration', () {
    final video = VideoInfo.fromProbe(
      {
        'streams': [
          {
            'codec_type': 'video',
            'disposition': {'attached_pic': 1},
            'width': 10,
            'height': 10,
          },
          {
            'codec_type': 'video',
            'width': 1920,
            'height': 1080,
            'avg_frame_rate': '0/0',
            'r_frame_rate': '60/1',
            'side_data_list': [
              {'rotation': -90},
            ],
            'color_transfer': 'smpte2084',
          },
        ],
        'format': {'duration': '42'},
      },
      path: 'video.mov',
      name: 'video.mov',
      bytes: 5000000,
    );
    expect(video.width, 1920);
    expect(video.rotation, -90);
    expect(video.fps, 60);
    expect(video.hdr, isTrue);
    expect(video.hasAudio, isFalse);
  });
  test('invalid or audio-only media is rejected', () {
    for (final json in <Map<String, dynamic>>[
      {
        'streams': [
          {'codec_type': 'audio'},
        ],
      },
      {
        'streams': [
          {'codec_type': 'video', 'width': 1920, 'height': 1080},
        ],
        'format': {'duration': 'NaN'},
      },
    ]) {
      expect(
        () => VideoInfo.fromProbe(json, path: 'x', name: 'x', bytes: 1),
        throwsA(isA<VideoException>()),
      );
    }
  });
  test(
    'output is compatible and input paths are passed as single arguments',
    () {
      final video = source();
      final plan = CompressionPlan.recommend(
        video,
        VideoGoal.compact,
        VideoContent.everyday,
      );
      final args = plan.arguments(video, '/local/folder with spaces/video.mp4');
      expect(args[args.indexOf('-i') + 1], video.path);
      expect(args.last, '/local/folder with spaces/video.mp4');
      expect(args, containsAll(['libx264', 'aac', '-n', '+faststart', '-1']));
      expect(args[args.indexOf('-vf') + 1], contains('format=yuv420p'));
    },
  );
}
