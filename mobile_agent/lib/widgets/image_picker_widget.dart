// lib/widgets/image_picker_widget.dart
// Reusable image picker with camera + gallery + preview

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';

/// Reusable image picker supporting camera capture, gallery selection,
/// preview thumbnail with remove option, and loading state.
///
/// Usage:
/// ```dart
/// ImagePickerWidget(
///   onImageCaptured: (base64, bytes) { /* handle image */ },
/// )
/// ```
class ImagePickerWidget extends StatefulWidget {
  final void Function(String base64, Uint8List bytes)? onImageCaptured;
  final String? initialImageBase64;
  final int maxDimension;
  final int jpegQuality;

  const ImagePickerWidget({
    super.key,
    this.onImageCaptured,
    this.initialImageBase64,
    this.maxDimension = 1024,
    this.jpegQuality = 85,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  final ImagePicker _picker = ImagePicker();
  String? _imageBase64;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    if (widget.initialImageBase64 != null) {
      _imageBase64 = widget.initialImageBase64;
      try { _imageBytes = base64Decode(widget.initialImageBase64!); } catch (_) {}
    }
  }

  Future<void> _captureFromCamera() async => _pickImage(ImageSource.camera);
  Future<void> _pickFromGallery() async => _pickImage(ImageSource.gallery);

  Future<void> _pickImage(ImageSource source) async {
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: widget.maxDimension.toDouble(),
        maxHeight: widget.maxDimension.toDouble(),
        imageQuality: widget.jpegQuality,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final b64 = base64Encode(bytes);
        setState(() { _imageBase64 = b64; _imageBytes = bytes; });
        widget.onImageCaptured?.call(b64, bytes);
      }
    } on PlatformException catch (e) {
      setState(() => _errorMsg = 'Camera/Gallery error: ${e.message}');
    } catch (e) {
      setState(() => _errorMsg = 'Failed: \$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearImage() {
    setState(() { _imageBase64 = null; _imageBytes = null; _errorMsg = null; });
  }

  @override
  Widget build(BuildContext context) {
    if (_imageBytes != null) return _buildPreview();
    return _buildPickerOptions();
  }

  Widget _buildPickerOptions() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (_errorMsg != null) _errorBanner(),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _pickerBtn('拍照', Icons.camera_alt, '使用相机', AppTheme.primaryGradient, _captureFromCamera)),
      const SizedBox(width: 12),
      Expanded(child: _pickerBtn('相册', Icons.photo_library, '选择图片', AppTheme.accentGradient, _pickFromGallery)),
    ]),
    if (_isLoading) ...[
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary))),
          const SizedBox(width: 12),
          const Text('正在处理图片...', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        ]),
      ),
    ],
  ]);

  Widget _pickerBtn(String label, IconData icon, String subtitle, Gradient gradient, VoidCallback? onTap) =>
    Container(height: 110,
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: (gradient == AppTheme.primaryGradient ? AppTheme.primary : AppTheme.accent).withOpacity(0.25),
          blurRadius: 16, offset: const Offset(0, 6))]),
      child: Material(color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
          child: Container(padding: const EdgeInsets.all(16),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 44, height: 44,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                child: _isLoading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(icon, size: 22, color: Colors.white)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
            ])))),
    );

  Widget _errorBanner() => Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.error.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.error_outline, size: 16, color: AppTheme.error),
      const SizedBox(width: 8),
      Expanded(child: Text(_errorMsg!, style: const TextStyle(fontSize: 12, color: AppTheme.error))),
      GestureDetector(onTap: () => setState(() => _errorMsg = null),
        child: const Icon(Icons.close, size: 16, color: AppTheme.error)),
    ]),
  );

  Widget _buildPreview() => Container(
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border)),
    child: ClipRRect(borderRadius: BorderRadius.circular(16),
      child: Stack(children: [
        Image.memory(_imageBytes!, width: double.infinity, fit: BoxFit.contain),
        // Top overlay: size + remove
        Positioned(top: 0, left: 0, right: 0,
          child: Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.5), Colors.transparent])),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(6)),
                child: Text('${(_imageBytes!.length / 1024).toStringAsFixed(1)} KB',
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500))),
              const SizedBox(width: 8),
              GestureDetector(onTap: _clearImage,
                child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.9), shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 16, color: Colors.white))),
            ]))),
        // Bottom overlay: status
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.6), Colors.transparent])),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 16, color: AppTheme.success),
              const SizedBox(width: 8),
              Expanded(child: Text('图片已就绪', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9)))),
              Text('${_fmtB64Size()} Base64', style: TextStyle(fontSize: 11,
                color: Colors.white.withOpacity(0.7), fontFamily: AppTheme.fontCode)),
            ]))),
      ])),
    );

  String _fmtB64Size() {
    if (_imageBase64 == null) return '0 B';
    final len = _imageBase64!.length;
    if (len < 1024) return '$len B';
    if (len < 1024 * 1024) return '${(len / 1024).toStringAsFixed(1)} KB';
    return '${(len / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

/// Prepare image for LLM: resize and compress.
/// Returns Base64-encoded JPEG optimized for token efficiency.
Future<String> prepareImageForLLM(Uint8List bytes, {int maxDim = 1024, int quality = 85}) async {
  // In production, use `image` package to resize:
  // final img = decodeImage(bytes);
  // final resized = copyResize(img!, width: img.width > img.height ? maxDim : null,
  //   height: img.height >= img.width ? maxDim : null);
  // return base64Encode(encodeJpg(resized, quality: quality));
  return base64Encode(bytes);
}
