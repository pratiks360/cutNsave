import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../state/app_state.dart';
import 'edit_article_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  String? _path;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick(ImageSource.camera, first: true));
  }

  Future<void> _pick(ImageSource source, {bool first = false}) async {
    final file = await _picker.pickImage(source: source, maxWidth: 2400, imageQuality: 90);
    if (!mounted) return;
    if (file == null) {
      if (first) Navigator.pop(context);
      return;
    }
    setState(() => _path = file.path);
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('scan'))),
      body: path == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: InteractiveViewer(child: Image.file(File(path)))),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      FilledButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditArticleScreen.scan(imagePath: path),
                          ),
                        ),
                        child: Text(context.t('use_photo')),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.camera_alt),
                              label: Text(context.t('retake')),
                              onPressed: () => _pick(ImageSource.camera),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.photo_library),
                              label: Text(context.t('gallery')),
                              onPressed: () => _pick(ImageSource.gallery),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
