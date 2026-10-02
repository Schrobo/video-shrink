import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) binding.ensureSemantics();
  runApp(const VideoShrinkApp());
}
