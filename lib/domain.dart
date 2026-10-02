import 'dart:math' as math;

const localVideoFormats =
    'mov,matroska,webm,avi,mpegts,mpeg,mpegvideo,flv,ogg,asf,rm,nut,h264,hevc';

enum VideoGoal {
  compact('WhatsApp', 15000000),
  quality('Mehr Qualität', 64000000);

  const VideoGoal(this.label, this.maxBytes);
  final String label;
  final int maxBytes;
}

enum VideoContent { everyday, text }

class VideoInfo {
  const VideoInfo({
    required this.path,
    required this.name,
    required this.bytes,
    required this.duration,
    required this.width,
    required this.height,
    this.fps = 30,
    this.hasAudio = true,
    this.hdr = false,
    this.rotation = 0,
    this.sampleAspectRatio = 1,
  });
  final String path, name;
  final int bytes, width, height, rotation;
  final double duration, fps, sampleAspectRatio;
  final bool hasAudio, hdr;
  double get displayWidth => rotation.abs() % 180 == 90
      ? height.toDouble()
      : width * sampleAspectRatio;
  double get displayHeight => rotation.abs() % 180 == 90
      ? width * sampleAspectRatio
      : height.toDouble();

  static VideoInfo fromProbe(
    Map<String, dynamic> json, {
    required String path,
    required String name,
    required int bytes,
  }) {
    final streams = (json['streams'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final video = streams
        .where(
          (s) =>
              s['codec_type'] == 'video' &&
              (s['disposition']?['attached_pic'] ?? 0) != 1,
        )
        .firstOrNull;
    if (video == null) {
      throw const VideoException(
        'Diese Datei enthält kein Video. Wähle eine Videodatei aus.',
      );
    }
    double number(Object? v, [double fallback = 0]) =>
        double.tryParse('$v') ?? fallback;
    double ratio(Object? v, double fallback) {
      final parts = '$v'.split(RegExp('[:/]'));
      if (parts.length != 2 || number(parts[1]) <= 0) return fallback;
      return number(parts[0]) / number(parts[1]);
    }

    final duration = number(
      video['duration'],
      number(json['format']?['duration']),
    );
    final width = number(video['width']).toInt(),
        height = number(video['height']).toInt();
    if (!duration.isFinite || duration <= 0 || width < 2 || height < 2) {
      throw const VideoException(
        'Länge oder Auflösung konnten nicht gelesen werden. Wähle eine andere Datei.',
      );
    }
    final side = video['side_data_list'] as List? ?? [];
    final rotation =
        side
            .whereType<Map>()
            .map((s) => s['rotation'])
            .where((v) => v != null)
            .firstOrNull ??
        video['tags']?['rotate'];
    final sar = ratio(video['sample_aspect_ratio'], 1);
    final fps = ratio(
      video['avg_frame_rate'],
      ratio(video['r_frame_rate'], 30),
    );
    return VideoInfo(
      path: path,
      name: name,
      bytes: bytes,
      duration: duration,
      width: width,
      height: height,
      fps: fps.isFinite && fps > 0 ? fps : 30,
      hasAudio: streams.any((s) => s['codec_type'] == 'audio'),
      hdr: ['smpte2084', 'arib-std-b67'].contains(video['color_transfer']),
      rotation: number(rotation).round(),
      sampleAspectRatio: sar.isFinite && sar > 0 ? sar : 1,
    );
  }
}

class CompressionPlan {
  const CompressionPlan({
    required this.width,
    required this.height,
    required this.fps,
    required this.videoKbps,
    required this.audioKbps,
    required this.goal,
    required this.content,
    this.warning,
  });
  final int width, height, fps, videoKbps, audioKbps;
  final VideoGoal goal;
  final VideoContent content;
  final String? warning;
  String get resolution => '$width × $height';
  bool get needsLargerBudget => videoKbps < 90;

  static CompressionPlan recommend(
    VideoInfo video,
    VideoGoal goal,
    VideoContent content,
  ) {
    final audio = video.hasAudio ? 64 : 0;
    final available =
        (goal.maxBytes * 8 * .94 / video.duration / 1000).floor() - audio;
    final fps = math.min(30, math.max(1, video.fps.round()));
    final maxSide = content == VideoContent.text || goal == VideoGoal.quality
        ? 1920
        : 1280;
    final ratio = video.displayWidth / video.displayHeight;
    int width = 2, height = 2;
    for (final side in [1920, 1280, 960, 854, 640, 426]) {
      if (side > maxSide) continue;
      final scale = math.min(
        1.0,
        side / math.max(video.displayWidth, video.displayHeight),
      );
      final long = math.max(
        2,
        (math.max(video.displayWidth, video.displayHeight) * scale / 2)
                .floor() *
            2,
      );
      width = ratio >= 1 ? long : math.max(2, (long * ratio / 2).floor() * 2);
      height = ratio >= 1 ? math.max(2, (long / ratio / 2).floor() * 2) : long;
      final minimum =
          width *
          height *
          fps *
          (content == VideoContent.text ? .009 : .012) /
          1000;
      if (available >= minimum) break;
    }
    final String? warning = available < 90
        ? goal == VideoGoal.compact
              ? 'Für diese Länge reichen ${formatBytes(goal.maxBytes)} kaum aus. Wähle „Mehr Qualität“ oder teile das Video vorher in kürzere Abschnitte.'
              : 'Auch 64 MB reichen für diese Länge kaum aus. Teile das Video vorher in kürzere Abschnitte.'
        : content == VideoContent.text && math.max(width, height) < 1280
        ? goal == VideoGoal.compact
              ? 'Kleine Schrift kann schwer lesbar werden. „Mehr Qualität“ erlaubt eine höhere Auflösung.'
              : 'Kleine Schrift kann schwer lesbar werden. Teile das Video für eine höhere Auflösung in kürzere Abschnitte.'
        : math.max(width, height) < 854
        ? goal == VideoGoal.compact
              ? 'Die lange Laufzeit erfordert eine niedrigere Auflösung. Mit „Mehr Qualität“ bleiben mehr Details erhalten.'
              : 'Die lange Laufzeit erfordert eine niedrigere Auflösung. Kürzere Abschnitte erhalten mehr Details.'
        : null;
    return CompressionPlan(
      width: width,
      height: height,
      fps: fps,
      videoKbps: math.max(
        1,
        math.min(available, goal == VideoGoal.quality ? 4000 : 1600),
      ),
      audioKbps: audio,
      goal: goal,
      content: content,
      warning: warning,
    );
  }

  List<String> arguments(
    VideoInfo video,
    String output, {
    double bitrateFactor = 1,
  }) {
    final bitrate = math.max(1, (videoKbps * bitrateFactor).floor());
    final filters = [
      if (video.hdr) ...[
        'zscale=t=linear:npl=100',
        'format=gbrpf32le',
        'zscale=p=bt709',
        'tonemap=hable:desat=0',
        'zscale=t=bt709:m=bt709:r=tv',
      ],
      'scale=$width:$height:flags=lanczos',
      'setsar=1',
      'fps=$fps',
      'format=yuv420p',
    ];
    return [
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-n',
      '-protocol_whitelist',
      'file,pipe',
      '-format_whitelist',
      localVideoFormats,
      '-i',
      video.path,
      '-map',
      '0:V:0',
      '-map',
      '0:a:0?',
      '-sn',
      '-dn',
      '-t',
      video.duration.toStringAsFixed(3),
      '-vf',
      filters.join(','),
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      content == VideoContent.text ? '24' : '27',
      '-maxrate',
      '${bitrate}k',
      '-bufsize',
      '${bitrate * 2}k',
      if (content == VideoContent.text) ...['-tune', 'stillimage'],
      if (video.hasAudio) ...[
        '-c:a',
        'aac',
        '-b:a',
        '${audioKbps}k',
        '-ac',
        '2',
      ],
      if (video.hdr) ...[
        '-color_primaries',
        'bt709',
        '-color_trc',
        'bt709',
        '-colorspace',
        'bt709',
      ],
      '-map_metadata',
      '-1',
      '-map_chapters',
      '-1',
      '-movflags',
      '+faststart',
      '-progress',
      'pipe:1',
      output,
    ];
  }
}

class VideoException implements Exception {
  const VideoException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ConversionResult {
  const ConversionResult(
    this.path,
    this.bytes, {
    this.simulated = false,
    this.unchanged = false,
  });
  final String path;
  final int bytes;
  final bool simulated;
  final bool unchanged;
}

VideoInfo exampleVideo({String name = 'Bildschirmaufnahme.mp4'}) => VideoInfo(
  path: name,
  name: name,
  bytes: 48140472,
  duration: 243.9,
  width: 1920,
  height: 1054,
);
String formatBytes(int bytes) =>
    '${(bytes / 1000000).toStringAsFixed(1).replaceAll('.', ',')} MB';
String formatDuration(double seconds) =>
    '${seconds.round() ~/ 60}:${(seconds.round() % 60).toString().padLeft(2, '0')} Min.';
