import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/services/html_render_provider.dart';

void main() {
  test('render request carries the artifact contract', () {
    final request = HtmlRenderRequest(
      sourceUrl: 'file:///workspace/index.html',
      viewportWidth: 390,
      viewportHeight: 844,
      deviceScaleFactor: 2,
      format: HtmlRenderFormat.mp4,
      inlineHtml: '<!doctype html><html></html>',
    );

    expect(request.toPlatformArguments(), containsPair('format', 'mp4'));
    expect(
        request.toPlatformArguments(), containsPair('inlineHtml', isNotEmpty));
    expect(request.format.mimeType, 'video/mp4');
  });

  test('PPTX provider carries slide navigation and visual mode', () {
    const request = HtmlRenderRequest(
      sourceUrl: 'file:///workspace/deck/index.html',
      viewportWidth: 1920,
      viewportHeight: 1080,
      format: HtmlRenderFormat.pptx,
      slideCount: 8,
      slideAspectRatio: '16:9',
      pptxMode: HtmlPptxMode.visual,
    );
    final arguments = request.toPlatformArguments();
    final provider = HtmlPptxRenderProvider(
      endpoint: Uri.parse('http://127.0.0.1:8792/v1/render/pptx'),
    );

    expect(arguments, containsPair('format', 'pptx'));
    expect(arguments, containsPair('slideCount', 8));
    expect(arguments, containsPair('pptxMode', 'visual'));
    expect(provider.engine, 'html_pptx');
    expect(provider.outputFormat, HtmlRenderFormat.pptx);
  });

  test('fromBytes and artifact store preserve verified bytes', () async {
    final request = HtmlRenderRequest(
      sourceUrl: 'file:///workspace/index.html',
      viewportWidth: 390,
      viewportHeight: 844,
      format: HtmlRenderFormat.pdf,
    );
    final artifact = await HtmlRenderArtifact.fromBytes(
      <int>[37, 80, 68, 70, 45, 49, 46, 55],
      request,
      backend: 'test_worker',
    );
    final directory =
        await Directory.systemTemp.createTemp('mobilecode-artifact-test-');
    addTearDown(() => directory.delete(recursive: true));

    final stored = await const HtmlArtifactStore().materialize(
      artifact,
      directory: directory,
      fileName: 'preview output.pdf',
    );

    expect(stored.path, endsWith('preview_output.pdf'));
    expect(stored.format, HtmlRenderFormat.pdf);
    expect(stored.bytes, 8);
    expect(stored.sha256, isNotEmpty);
    expect(await File(stored.path).readAsBytes(),
        <int>[37, 80, 68, 70, 45, 49, 46, 55]);
  });

  test('HyperFrames provider downloads and verifies a worker artifact',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method == 'POST') {
        await request.drain();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'backend': 'test_hyperframes_worker',
            'artifactUrl':
                'http://127.0.0.1:${server.port}/v1/render/artifacts/test',
            'metadata': {'engine': 'hyperframes'},
          }),
        );
      } else {
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add(<int>[0, 1, 2, 3]);
      }
      await request.response.close();
    });

    final artifact = await HyperFramesHtmlRenderProvider(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/render/html'),
    ).render(
      const HtmlRenderRequest(
        sourceUrl: 'http://worker-visible.test/index.html',
        viewportWidth: 390,
        viewportHeight: 844,
        format: HtmlRenderFormat.mp4,
      ),
    );

    expect(artifact.backend, 'test_hyperframes_worker');
    expect(artifact.format, HtmlRenderFormat.mp4);
    expect(artifact.mimeType, 'video/mp4');
    expect(artifact.bytes, 4);
    expect(artifact.sha256, hasLength(64));
  });
}
