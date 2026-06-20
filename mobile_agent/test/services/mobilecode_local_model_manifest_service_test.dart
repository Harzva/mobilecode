import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/mobilecode_local_model_manifest_service.dart';

void main() {
  group('MobileCodeLocalModelManifest', () {
    test('parses candidate models and exposes safe download links', () {
      final manifest = MobileCodeLocalModelManifest.fromJson({
        'schemaVersion': 1,
        'updatedAt': '2026-06-20T00:00:00Z',
        'docsUrl':
            'https://harzva.github.io/mobilecode/mobilecode-local-models.json',
        'models': [
          {
            'id': 'qwen3-0.6b-executorch',
            'displayName': 'Qwen3 0.6B ExecuTorch',
            'status': 'candidate',
            'runtime': 'executorch',
            'platforms': ['android'],
            'format': 'pte',
            'downloadPageUrl': 'https://huggingface.co/example/qwen3',
            'modelUrl': '',
            'tokenizerUrl': '',
            'modelSha256': '',
            'tokenizerSha256': '',
            'approxBytes': 500000000,
            'minRamMb': 4096,
            'license': 'check upstream',
            'notes': ['User installed; not bundled in APK.'],
          },
        ],
      }, sourceUrl: MobileCodeLocalModelManifestService.defaultManifestUrl);

      expect(manifest.schemaVersion, 1);
      expect(manifest.models, hasLength(1));
      expect(manifest.models.first.id, 'qwen3-0.6b-executorch');
      expect(manifest.models.first.canDirectDownload, isFalse);
      expect(
        manifest.models.first.primaryDownloadUrl,
        'https://huggingface.co/example/qwen3',
      );
      expect(manifest.readyModelCount, 0);
      expect(manifest.sourceUrl,
          MobileCodeLocalModelManifestService.defaultManifestUrl);
    });

    test('counts ready direct-download models only when artifacts are verified',
        () {
      final manifest = MobileCodeLocalModelManifest.fromJson({
        'models': [
          {
            'id': 'ready-model',
            'displayName': 'Ready Model',
            'status': 'ready',
            'runtime': 'executorch',
            'platforms': ['android'],
            'format': 'pte',
            'modelUrl': 'https://example.com/model.pte',
            'tokenizerUrl': 'https://example.com/tokenizer.json',
            'modelSha256':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'tokenizerSha256':
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          },
          {
            'id': 'missing-checksum',
            'displayName': 'Missing Checksum',
            'status': 'ready',
            'runtime': 'executorch',
            'platforms': ['android'],
            'format': 'pte',
            'modelUrl': 'https://example.com/model.pte',
          },
        ],
      });

      expect(manifest.readyModelCount, 1);
      expect(manifest.models.first.canDirectDownload, isTrue);
      expect(manifest.models.last.canDirectDownload, isFalse);
    });
  });
}
