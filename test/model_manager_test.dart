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
    expect((await manager.verifiedFileFor(package)).path,
        '${temporaryDirectory.path}/basic/model.bin');
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
      sourceRevision: 'a' * 40,
    );
    final manager = ModelManager(rootDirectory: temporaryDirectory);

    await manager.writeManifest(<ModelPackage>[package]);
    final loaded = await manager.readManifest();

    expect(loaded.single.toMap(), package.toMap());
    expect(loaded.single.isPinned, isTrue);
    expect(loaded.single.isImmutable, isFalse);
  });

  test('accepts catalog entries pinned to an immutable HTTPS revision', () {
    final package = defaultModelCatalog().first;

    expect(package.isImmutable, isTrue);
    expect(package.sourceRevision, hasLength(40));
    expect(package.sourceUrl, contains('/resolve/${package.sourceRevision}/'));
  });

  test('declares the complete Supertonic 3 bundle as immutable', () {
    final bundle = supertonic3Bundle(CapabilityProfile.basic);

    expect(bundle.artifacts, hasLength(7));
    expect(bundle.sizeBytes, 398652950);
    expect(bundle.isImmutable, isTrue);
  });

  test('rejects mutable download sources even with valid file metadata',
      () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-mutable-source-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final package = ModelPackage(
      id: 'mutable-model',
      profile: CapabilityProfile.basic,
      component: ModelComponent.dialogue,
      version: '1',
      fileName: 'model.gguf',
      sha256: 'a' * 64,
      license: 'Apache-2.0',
      sizeBytes: 42,
      sourceUrl: 'https://example.test/model.gguf',
    );
    final manager = ModelManager(rootDirectory: temporaryDirectory);

    expect(package.isImmutable, isFalse);
    await expectLater(
      manager.download(package),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('imports and activates a verified multi-file model bundle', () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('learnit-bundle-');
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final sourceDirectory = Directory('${temporaryDirectory.path}/sources');
    await sourceDirectory.create();
    final firstSource = File('${sourceDirectory.path}/first.bin');
    final secondSource = File('${sourceDirectory.path}/second.json');
    final firstBytes = <int>[1, 2, 3];
    final secondBytes = <int>[4, 5, 6, 7];
    await firstSource.writeAsBytes(firstBytes);
    await secondSource.writeAsBytes(secondBytes);
    final revision = 'b' * 40;
    final bundle = ModelBundle(
      id: 'tts-bundle',
      profile: CapabilityProfile.basic,
      component: ModelComponent.speechSynthesizer,
      version: revision,
      artifacts: <ModelArtifact>[
        ModelArtifact(
          id: 'first',
          relativePath: 'onnx/first.bin',
          version: revision,
          sha256: sha256.convert(firstBytes).toString(),
          license: 'MIT',
          sizeBytes: firstBytes.length,
          sourceUrl: 'https://example.test/resolve/$revision/onnx/first.bin',
          sourceRevision: revision,
        ),
        ModelArtifact(
          id: 'second',
          relativePath: 'onnx/second.json',
          version: revision,
          sha256: sha256.convert(secondBytes).toString(),
          license: 'MIT',
          sizeBytes: secondBytes.length,
          sourceUrl: 'https://example.test/resolve/$revision/onnx/second.json',
          sourceRevision: revision,
        ),
      ],
    );
    final manager = ModelManager(rootDirectory: temporaryDirectory);

    final imported = await manager.importBundle(
      bundle,
      <String, File>{'first': firstSource, 'second': secondSource},
    );
    expect(imported.ready, isTrue);
    await manager.activateBundle(bundle);
    expect(
      (await manager
              .activeBundles(CapabilityProfile.basic, <ModelBundle>[bundle]))
          .single
          .id,
      'tts-bundle',
    );

    await secondSource.writeAsBytes(<int>[9, 8, 7]);
    await expectLater(
      manager.importBundle(
        bundle,
        <String, File>{'first': firstSource, 'second': secondSource},
      ),
      throwsA(isA<StateError>()),
    );
    expect((await manager.verifyBundle(bundle)).ready, isTrue);
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
