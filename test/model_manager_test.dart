import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learnit/services/model_manager.dart';

void main() {
  test('imports only a package whose SHA-256 matches', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-model-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final source = File('${temporaryDirectory.path}/model.bin');
    final bytes = <int>[1, 2, 3, 4, 5];
    await source.writeAsBytes(bytes);
    final hash = sha256.convert(bytes).toString();
    final package = ModelPackage(
      id: 'test-model',
      profile: CapabilityProfile.basic,
      component: ModelComponent.dialogue,
      version: 'test',
      fileName: 'model.bin',
      sha256: hash,
      license: 'MIT',
      sizeBytes: bytes.length,
      sourceUrl: 'local://test',
    );

    final manager = ModelManager(rootDirectory: temporaryDirectory);
    final result = await manager.importFile(package, source);

    expect(result.ready, isTrue);
    expect(result.actualSizeBytes, bytes.length);
  });

  test('rejects an invalid package hash', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-model-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final source = File('${temporaryDirectory.path}/model.bin');
    await source.writeAsBytes(<int>[9, 8, 7]);
    final package = const ModelPackage(
      id: 'bad-model',
      profile: CapabilityProfile.basic,
      component: ModelComponent.dialogue,
      version: 'test',
      fileName: 'bad.bin',
      sha256: 'not-the-real-hash',
      license: 'MIT',
      sizeBytes: 3,
      sourceUrl: 'local://test',
    );
    final manager = ModelManager(rootDirectory: temporaryDirectory);

    await expectLater(
      manager.importFile(package, source),
      throwsA(isA<StateError>()),
    );
  });

  test('keeps the previous package when a replacement is invalid', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-atomic-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final source = File('${temporaryDirectory.path}/model.bin');
    final validBytes = <int>[1, 2, 3];
    await source.writeAsBytes(validBytes);
    final package = ModelPackage(
      id: 'atomic-model',
      profile: CapabilityProfile.basic,
      component: ModelComponent.dialogue,
      version: '1',
      fileName: 'model.bin',
      sha256: sha256.convert(validBytes).toString(),
      license: 'MIT',
      sizeBytes: validBytes.length,
      sourceUrl: 'https://example.test/model.bin',
    );
    final manager = ModelManager(rootDirectory: temporaryDirectory);
    await manager.importFile(package, source);

    await source.writeAsBytes(<int>[9, 8, 7]);
    await expectLater(
      manager.importFile(package, source),
      throwsA(isA<StateError>()),
    );

    expect((await manager.verify(package)).ready, isTrue);
    expect(
      await File('${temporaryDirectory.path}/basic/model.bin').readAsBytes(),
      validBytes,
    );
  });

  test('round trips a model manifest', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-manifest-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final package = ModelPackage(
      id: 'manifest-model',
      profile: CapabilityProfile.advanced,
      component: ModelComponent.dialogue,
      version: '2026.09',
      fileName: 'model.gguf',
      sha256: 'a' * 64,
      license: 'Apache-2.0',
      sizeBytes: 42,
      sourceUrl: 'https://example.test/model.gguf',
    );
    final manager = ModelManager(rootDirectory: temporaryDirectory);

    await manager.writeManifest(<ModelPackage>[package]);
    final loaded = await manager.readManifest();

    expect(loaded.single.toMap(), package.toMap());
    expect(loaded.single.isPinned, isTrue);
  });

  test('does not download a package with placeholder metadata', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-download-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    const package = ModelPackage(
      id: 'pending-model',
      profile: CapabilityProfile.basic,
      component: ModelComponent.dialogue,
      version: 'pending-spike',
      fileName: 'model.gguf',
      sha256: 'PENDING_SHA256',
      license: 'Apache-2.0',
      sizeBytes: 0,
      sourceUrl: 'https://example.test/model.gguf',
    );
    final manager = ModelManager(rootDirectory: temporaryDirectory);

    await expectLater(
      manager.download(package),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('keeps one active package per component', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-active-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final bytes = <int>[4, 5, 6];
    final hash = sha256.convert(bytes).toString();
    final source = File('${temporaryDirectory.path}/source.bin');
    await source.writeAsBytes(bytes);
    final packages = <ModelPackage>[
      ModelPackage(
        id: 'stt',
        profile: CapabilityProfile.basic,
        component: ModelComponent.speechRecognizer,
        version: '1',
        fileName: 'stt.bin',
        sha256: hash,
        license: 'MIT',
        sizeBytes: bytes.length,
        sourceUrl: 'https://example.test/stt.bin',
      ),
      ModelPackage(
        id: 'llm',
        profile: CapabilityProfile.basic,
        component: ModelComponent.dialogue,
        version: '1',
        fileName: 'llm.bin',
        sha256: hash,
        license: 'Apache-2.0',
        sizeBytes: bytes.length,
        sourceUrl: 'https://example.test/llm.bin',
      ),
    ];
    final manager = ModelManager(rootDirectory: temporaryDirectory);
    for (final package in packages) {
      await manager.importFile(package, source);
      await manager.activate(package);
    }

    final active = await manager.activePackages(
      CapabilityProfile.basic,
      packages,
    );
    expect(active.map((package) => package.id),
        containsAll(<String>['stt', 'llm']));
  });
}
