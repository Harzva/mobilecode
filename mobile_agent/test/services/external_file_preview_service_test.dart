import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/external_file_preview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobilecode/system_tools');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('classifies html even when WeChat exposes an opaque extension', () async {
    final dir = await Directory.systemTemp.createTemp('mobilecode_preview_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/wechat_payload.bin');
    await file.writeAsString('<!doctype html><html><body>Hello</body></html>');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'consumePendingSharedFile');
      return {
        'path': file.path,
        'displayName': 'wechat_payload.bin',
        'mimeType': 'application/octet-stream',
        'sizeBytes': await file.length(),
        'source': 'android_intent',
      };
    });

    final preview = await ExternalFilePreviewService.instance.consumePendingFile();

    expect(preview, isNotNull);
    expect(preview!.kind, ExternalPreviewKind.html);
    expect(preview.displayName, 'wechat_payload.bin');
  });

  test('classifies markdown by content when extension is missing', () async {
    final dir = await Directory.systemTemp.createTemp('mobilecode_preview_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/message');
    await file.writeAsString('# 周报\n\n- 已完成 HTML 预览\n- 待验证微信入口');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return {
        'path': file.path,
        'displayName': 'message',
        'mimeType': 'application/octet-stream',
        'sizeBytes': await file.length(),
      };
    });

    final preview = await ExternalFilePreviewService.instance.consumePendingFile();

    expect(preview, isNotNull);
    expect(preview!.kind, ExternalPreviewKind.markdown);
  });

  test('keeps real binary files out of text preview modes', () async {
    final dir = await Directory.systemTemp.createTemp('mobilecode_preview_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/payload.dat');
    await file.writeAsBytes([0, 159, 0, 255, 216, 255, 0, 7, 8, 9]);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return {
        'path': file.path,
        'displayName': 'payload.dat',
        'mimeType': 'application/octet-stream',
        'sizeBytes': await file.length(),
      };
    });

    final preview = await ExternalFilePreviewService.instance.consumePendingFile();

    expect(preview, isNotNull);
    expect(preview!.kind, ExternalPreviewKind.unsupported);
    expect(preview.isTextReadable, isFalse);
  });

  test('returns null when Android has no pending shared file', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final preview = await ExternalFilePreviewService.instance.consumePendingFile();

    expect(preview, isNull);
  });
}
