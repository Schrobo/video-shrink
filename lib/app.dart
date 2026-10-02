import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'backend.dart';
import 'domain.dart';

const violet = Color(0xFF7516F8),
    ink = Color(0xFF1C1425),
    muted = Color(0xFF61596B);

class VideoShrinkApp extends StatelessWidget {
  const VideoShrinkApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Video Shrink',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFCFCFE),
      colorScheme: ColorScheme.fromSeed(
        seedColor: violet,
        surface: Colors.white,
      ),
      textTheme: ThemeData().textTheme.apply(bodyColor: ink, displayColor: ink),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: const VideoWindow(),
  );
}

class VideoWindow extends StatefulWidget {
  const VideoWindow({super.key});
  @override
  State<VideoWindow> createState() => _VideoWindowState();
}

class _VideoWindowState extends State<VideoWindow> {
  final backend = VideoBackend();
  VideoInfo? video;
  ConversionResult? result;
  VideoGoal goal = VideoGoal.compact;
  VideoContent content = VideoContent.everyday;
  bool dragging = false, busy = false, analyzing = false, choosing = false;
  bool optionsOpen = false;
  double progress = 0;
  String phase = '', error = '';
  CompressionPlan? get plan =>
      video == null ? null : CompressionPlan.recommend(video!, goal, content);

  Future<void> pick() async {
    if (busy || analyzing || choosing) return;
    setState(() {
      choosing = true;
      error = '';
    });
    try {
      final path = await backend.pickVideo();
      if (path != null && mounted) await load(path);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Die Dateiauswahl konnte nicht geöffnet werden. Ziehe das Video in das Fenster.',
        );
      }
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> load(String path) async {
    if (busy || analyzing) return;
    setState(() {
      analyzing = true;
      video = null;
      result = null;
      error = '';
    });
    try {
      final info = await backend.analyze(path);
      if (!mounted) return;
      setState(() {
        video = info;
        analyzing = false;
      });
      if (!plan!.needsLargerBudget) await compress();
    } on VideoException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          analyzing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Die Datei konnte nicht gelesen werden. Prüfe die Zugriffsrechte und wähle sie erneut aus.';
          analyzing = false;
        });
      }
    }
  }

  Future<void> compress() async {
    if (busy || video == null || plan!.needsLargerBudget) return;
    setState(() {
      busy = true;
      error = '';
      result = null;
      progress = 0;
      phase = 'Video verkleinern';
    });
    try {
      final converted = await backend.convert(video!, plan!, (value, label) {
        if (mounted) {
          setState(() {
            progress = value;
            phase = label;
          });
        }
      });
      if (mounted) setState(() => result = converted);
    } on VideoException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Das Video konnte nicht gespeichert werden. Prüfe Speicherplatz und Schreibrechte.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void reset() => setState(() {
    video = null;
    result = null;
    error = '';
  });
  @override
  void dispose() {
    backend.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): pick,
      const SingleActivator(LogicalKeyboardKey.keyO, meta: true): pick,
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelHeight =
                  constraints.maxHeight.clamp(360.0, 560.0) - 32;
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 640,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          key: const ValueKey('video-panel'),
                          color: dragging
                              ? const Color(0xFFF5EFFF)
                              : Colors.white,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: dragging
                                  ? violet
                                  : const Color(0xFFE8E3EF),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: panelHeight - 64,
                                child: video == null
                                    ? _dropZone()
                                    : Center(
                                        child: SingleChildScrollView(
                                          child: _videoCard(),
                                        ),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  24,
                                  16,
                                ),
                                child: Row(
                                  children: [
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: muted,
                                        minimumSize: const Size(0, 48),
                                      ),
                                      onPressed: busy || analyzing
                                          ? null
                                          : () => setState(
                                              () => optionsOpen = !optionsOpen,
                                            ),
                                      icon: Icon(
                                        optionsOpen
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        size: 18,
                                      ),
                                      label: const Text('Optionen'),
                                    ),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF7F5FA),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: goal.label,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    color: ink,
                                                  ),
                                                ),
                                                const TextSpan(
                                                  text: ' · Automatisch',
                                                ),
                                              ],
                                            ),
                                            textAlign: TextAlign.end,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: muted,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (optionsOpen)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    0,
                                    24,
                                    24,
                                  ),
                                  child: Column(
                                    children: [
                                      const Divider(
                                        height: 1,
                                        color: Color(0xFFEDE9F2),
                                      ),
                                      const SizedBox(height: 20),
                                      _settings(),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Das Original bleibt erhalten.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                        ),
                                      ),
                                      if (kIsWeb) ...[
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Die Vorschau verwendet Beispieldaten. Dateien werden nicht hochgeladen.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _examples(),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (error.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: _Notice(
                                error,
                                Icons.info_outline,
                                const Color(0xFF9C2835),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _dropZone() => DropTarget(
    enable: !busy && !analyzing && !choosing,
    onDragEntered: (_) => setState(() => dragging = true),
    onDragExited: (_) => setState(() => dragging = false),
    onDragDone: (details) {
      setState(() => dragging = false);
      if (details.files.length != 1) {
        setState(() => error = 'Bitte lege genau ein Video ab.');
        return;
      }
      unawaited(
        load(kIsWeb ? details.files.single.name : details.files.single.path),
      );
    },
    child: SizedBox.expand(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (analyzing)
                const CircularProgressIndicator()
              else
                Icon(
                  dragging
                      ? Icons.file_download_outlined
                      : Icons.video_file_outlined,
                  size: 48,
                  color: violet.withValues(alpha: .7),
                ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  analyzing
                      ? 'Video wird analysiert …'
                      : dragging
                      ? 'Hier ablegen'
                      : 'Video hier ablegen',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (analyzing)
                TextButton(
                  onPressed: backend.cancel,
                  child: const Text('Abbrechen'),
                )
              else
                FilledButton(
                  onPressed: choosing ? null : pick,
                  child: const Text('Datei auswählen'),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Für den Versand',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      SegmentedButton<VideoGoal>(
        segments: const [
          ButtonSegment(
            value: VideoGoal.compact,
            label: Text('WhatsApp · bis 15 MB'),
            icon: Icon(Icons.chat_bubble_outline, size: 16),
          ),
          ButtonSegment(
            value: VideoGoal.quality,
            label: Text('Mehr Qualität · bis 64 MB'),
          ),
        ],
        selected: {goal},
        showSelectedIcon: false,
        onSelectionChanged: busy || analyzing
            ? null
            : (values) => setState(() {
                goal = values.single;
                result = null;
              }),
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'Kleine Schrift besser erhalten',
          style: TextStyle(fontSize: 14),
        ),
        subtitle: const Text(
          'Für Bildschirmaufnahmen und Präsentationen',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        value: content == VideoContent.text,
        onChanged: busy || analyzing
            ? null
            : (value) => setState(() {
                content = value! ? VideoContent.text : VideoContent.everyday;
                result = null;
              }),
      ),
      if (!kIsWeb)
        TextButton.icon(
          onPressed: busy || analyzing
              ? null
              : () async {
                  await _fileAction(backend.chooseOutputDirectory);
                  if (mounted) setState(() {});
                },
          icon: const Icon(Icons.folder_outlined, size: 16),
          label: Text(
            backend.outputDirectory == null
                ? 'Ausgabeordner auswählen'
                : 'Ausgabeordner ändern',
          ),
        ),
    ],
  );

  Widget _videoCard() => Container(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.video_file_outlined, color: violet),
            const SizedBox(width: 12),
            Expanded(
              child: Tooltip(
                message: video!.name,
                child: Text(
                  video!.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            if (!busy)
              IconButton(
                onPressed: reset,
                tooltip: 'Anderes Video auswählen',
                icon: const Icon(Icons.close, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${formatBytes(video!.bytes)} · ${formatDuration(video!.duration)} · ${video!.width} × ${video!.height}',
          style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        if (result != null) ...[
          const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF28794F),
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            '${formatBytes(video!.bytes)} → ${formatBytes(result!.bytes)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${result!.unchanged
                ? 'Original bereits geeignet'
                : result!.bytes > video!.bytes
                ? 'Format angepasst'
                : '${((1 - result!.bytes / video!.bytes) * 100).round()} % kleiner'} · MP4 ${video!.hasAudio ? 'mit Ton' : 'ohne Ton'}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (result!.simulated)
            const _Notice(
              'Beispielergebnis. In der Desktop-App entsteht hier die echte MP4-Datei.',
              Icons.visibility_outlined,
              muted,
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      _fileAction(() => backend.open(result!.path)),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Video öffnen'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _fileAction(() => backend.reveal(result!.path)),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Ordner öffnen'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: reset,
            child: const Text('Nächstes Video auswählen'),
          ),
        ] else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(plan!.resolution, Icons.aspect_ratio),
              _Pill('${plan!.fps} fps', Icons.speed),
              _Pill('Ziel: bis ${formatBytes(goal.maxBytes)}', Icons.compress),
              if (video!.hdr) const _Pill('HDR → SDR', Icons.tonality),
            ],
          ),
          if (plan?.warning != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _Notice(
                plan!.warning!,
                Icons.info_outline,
                const Color(0xFF76551B),
              ),
            ),
          const SizedBox(height: 24),
          if (!busy)
            FilledButton(
              onPressed: () async {
                if (plan!.needsLargerBudget && goal == VideoGoal.quality) {
                  reset();
                  return;
                }
                if (plan!.needsLargerBudget) {
                  setState(() {
                    goal = VideoGoal.quality;
                    result = null;
                  });
                }
                if (!plan!.needsLargerBudget) await compress();
              },
              child: Text(
                plan!.needsLargerBudget
                    ? goal == VideoGoal.quality
                          ? 'Anderes Video auswählen'
                          : 'Mit mehr Qualität verkleinern'
                    : 'Video verkleinern',
              ),
            ),
          if (busy) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                phase,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${(progress * 100).floor()} %',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: muted,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: backend.cancel,
                  child: const Text('Abbrechen'),
                ),
              ],
            ),
          ],
        ],
      ],
    ),
  );

  Future<void> _fileAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Die Datei konnte nicht geöffnet werden. Du findest sie neben dem Original.',
        );
      }
    }
  }

  Widget _examples() => Column(
    children: [
      const Text(
        'Vorschau ausprobieren',
        style: TextStyle(fontSize: 12, color: muted),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          TextButton(
            onPressed: busy ? null : () => load('Bildschirmaufnahme.mp4'),
            child: const Text('Beispielvideo'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    video = const VideoInfo(
                      path: '',
                      name: 'Hochformat.mov',
                      bytes: 95000000,
                      duration: 42,
                      width: 2160,
                      height: 3840,
                      fps: 60,
                      hdr: true,
                    );
                    result = null;
                    error = '';
                  }),
            child: const Text('4K-Hochformat'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    video = const VideoInfo(
                      path: '',
                      name: 'Langes-Video.mp4',
                      bytes: 800000000,
                      duration: 2400,
                      width: 1920,
                      height: 1080,
                    );
                    result = null;
                    error = '';
                  }),
            child: const Text('Langes Video'),
          ),
        ],
      ),
    ],
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.icon);
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F0F7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: muted)),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, this.icon, this.color);
  final String text;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 13, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
