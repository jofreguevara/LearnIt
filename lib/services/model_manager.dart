import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum CapabilityProfile { basic, advanced }

enum ModelComponent { speechRecognizer, dialogue, speechSynthesizer }

final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

extension CapabilityProfileLabel on CapabilityProfile {
  String get value => this == CapabilityProfile.basic ? 'basic' : 'advanced';

  String get label => this == CapabilityProfile.basic ? 'Básico' : 'Avanzado';
}

extension ModelComponentLabel on ModelComponent {
  String get value => switch (this) {
        ModelComponent.speechRecognizer => 'stt',
        ModelComponent.dialogue => 'llm',
        ModelComponent.speechSynthesizer => 'tts',
      };
}

class ModelPackage {
  const ModelPackage({
    required this.id,
    required this.profile,
    required this.component,
    required this.version,
    required this.fileName,
    required this.sha256,
    required this.license,
    required this.sizeBytes,
    required this.sourceUrl,
  });

  final String id;
  final CapabilityProfile profile;
  final ModelComponent component;
  final String version;
  final String fileName;
  final String sha256;
  final String license;
  final int sizeBytes;
  final String sourceUrl;

  /// Returns a validation message for metadata that must be fixed before a
  /// package can become active. Importing a local test fixture does not need a
  /// network URL, so that check lives in [downloadError] instead.
  String? get metadataError {
    if (id.trim().isEmpty) {
      return 'El paquete debe tener un identificador.';
    }
    if (version.trim().isEmpty || version.toLowerCase() == 'pending-spike') {
      return 'El paquete $id necesita una versión fijada.';
    }
    if (fileName.trim().isEmpty ||
        fileName.contains('/') ||
        fileName.contains('\\') ||
        fileName.contains('\u0000') ||
        fileName == '.' ||
        fileName == '..') {
      return 'El nombre de archivo del paquete $id no es seguro.';
    }
    if (!_sha256Pattern.hasMatch(sha256)) {
      return 'El paquete $id necesita un SHA-256 hexadecimal de 64 caracteres.';
    }
    if (sizeBytes <= 0) {
      return 'El paquete $id necesita un tamaño instalado positivo.';
    }
    if (license.trim().isEmpty) {
      return 'El paquete $id necesita declarar su licencia.';
    }
    return null;
  }

  String? get downloadError {
    final metadata = metadataError;
    if (metadata != null) {
      return metadata;
    }
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Los paquetes deben descargarse por HTTPS desde una URL válida.';
    }
    return null;
  }

  bool get isPinned => metadataError == null;

  Map<String, Object?> toMap() => {
        'id': id,
        'profile': profile.value,
        'component': component.value,
        'version': version,
        'file_name': fileName,
        'sha256': sha256,
        'license': license,
        'size_bytes': sizeBytes,
        'source_url': sourceUrl,
      };

  factory ModelPackage.fromMap(Map<String, Object?> map) {
    final profileValue = map['profile'];
    final profile = CapabilityProfile.values
        .where((candidate) => candidate.value == profileValue)
        .firstOrNull;
    if (profile == null) {
      throw const FormatException('Perfil de modelo desconocido.');
    }

    final componentValue = map['component'];
    final component = ModelComponent.values
        .where((candidate) => candidate.value == componentValue)
        .firstOrNull;
    if (component == null) {
      throw const FormatException('Componente de modelo desconocido.');
    }

    final sizeValue = map['size_bytes'];
    if (sizeValue is! num) {
      throw const FormatException('El tamaño del modelo no es numérico.');
    }

    return ModelPackage(
      id: _requiredString(map, 'id'),
      profile: profile,
      component: component,
      version: _requiredString(map, 'version'),
      fileName: _requiredString(map, 'file_name'),
      sha256: _requiredString(map, 'sha256'),
      license: _requiredString(map, 'license'),
      sizeBytes: sizeValue.toInt(),
      sourceUrl: _requiredString(map, 'source_url'),
    );
  }
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw FormatException('Falta el campo de modelo "$key".');
  }
  return value;
}

class ModelVerification {
  const ModelVerification({
    required this.package,
    required this.installed,
    required this.hashMatches,
    this.sizeMatches = true,
    this.actualSizeBytes,
  });

  final ModelPackage package;
  final bool installed;
  final bool hashMatches;
  final bool sizeMatches;
  final int? actualSizeBytes;

  bool get ready => installed && hashMatches && sizeMatches;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest digest) => value = digest;

  @override
  void close() {}
}

/// Handles model packages without making network access part of inference.
/// Downloads can be added by the installer UI; inference only reads verified files.
class ModelManager {
  ModelManager({Directory? rootDirectory}) : _rootDirectory = rootDirectory;

  Directory? _rootDirectory;

  Future<Directory> _root() async {
    return _rootDirectory ??= Directory(
      path.join((await getApplicationSupportDirectory()).path, 'models'),
    );
  }

  Future<File> fileFor(ModelPackage package) async {
    final root = await _root();
    final directory = Directory(path.join(root.path, package.profile.value));
    await directory.create(recursive: true);
    return File(path.join(directory.path, package.fileName));
  }

  Future<ModelVerification> verify(ModelPackage package) async {
    final file = await fileFor(package);
    return _verifyFile(package, file);
  }

  Future<ModelVerification> _verifyFile(
    ModelPackage package,
    File file,
  ) async {
    if (!await file.exists()) {
      return ModelVerification(
          package: package, installed: false, hashMatches: false);
    }
    // Hash in chunks so checking a multi-gigabyte package does not duplicate
    // the model in Dart heap memory.
    final digestSink = _DigestSink();
    final converter = sha256.startChunkedConversion(digestSink);
    await for (final chunk in file.openRead()) {
      converter.add(chunk);
    }
    converter.close();
    final actualHash = digestSink.value?.toString() ?? '';
    final actualSize = await file.length();
    return ModelVerification(
      package: package,
      installed: true,
      hashMatches: actualHash.toLowerCase() == package.sha256.toLowerCase(),
      sizeMatches: package.sizeBytes <= 0 || actualSize == package.sizeBytes,
      actualSizeBytes: actualSize,
    );
  }

  Future<ModelVerification> importFile(
    ModelPackage package,
    File source,
  ) async {
    if (!await source.exists()) {
      throw ArgumentError.value(
        source.path,
        'source',
        'El archivo del modelo no existe.',
      );
    }
    final destination = await fileFor(package);
    final temporary = File('${destination.path}.part');
    try {
      await source.copy(temporary.path);
      final result = await _verifyFile(package, temporary);
      if (!result.ready) {
        throw StateError('El paquete ${package.id} no supera la verificación.');
      }
      if (await destination.exists()) {
        await destination.delete();
      }
      await temporary.rename(destination.path);
      return result;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<ModelVerification> download(
    ModelPackage package, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final validationError = package.downloadError;
    if (validationError != null) {
      throw ArgumentError.value(
        package.sourceUrl,
        'sourceUrl',
        validationError,
      );
    }
    final uri = Uri.parse(package.sourceUrl);
    final destination = await fileFor(package);
    final temporary = File('${destination.path}.part');
    final client = HttpClient();
    var transferCompleted = false;
    try {
      final existingBytes =
          await temporary.exists() ? await temporary.length() : 0;
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Descarga fallida (${response.statusCode}).',
            uri: uri);
      }
      final resumed = existingBytes > 0 && response.statusCode == 206;
      final totalBytes = response.contentLength < 0
          ? -1
          : response.contentLength + (resumed ? existingBytes : 0);
      var receivedBytes = resumed ? existingBytes : 0;
      final sink = temporary.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }
      } finally {
        await sink.close();
      }
      transferCompleted = true;
      final result = await _verifyFile(package, temporary);
      if (!result.ready) {
        await temporary.delete();
        throw StateError('El paquete ${package.id} no supera la verificación.');
      }
      if (await destination.exists()) {
        await destination.delete();
      }
      await temporary.rename(destination.path);
      return result;
    } finally {
      // Keep an interrupted .part file so the next attempt can resume it.
      // A completed transfer with a bad digest is removed above because it
      // cannot be resumed safely.
      if (transferCompleted && await temporary.exists()) {
        await temporary.delete();
      }
      client.close(force: true);
    }
  }

  Future<void> activate(ModelPackage package) async {
    final metadataError = package.metadataError;
    if (metadataError != null) {
      throw StateError('No se puede activar el paquete: $metadataError');
    }
    final verification = await verify(package);
    if (!verification.ready) {
      throw StateError(
          'El paquete ${package.id} no está instalado y verificado.');
    }
    final root = await _root();
    final marker = File(
      path.join(root.path, 'active-${package.profile.value}.json'),
    );
    final activePackages = <String, Object?>{};
    if (await marker.exists()) {
      try {
        final decoded = jsonDecode(await marker.readAsString());
        if (decoded is Map && decoded['packages'] is Map) {
          activePackages.addAll(
            (decoded['packages'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
        } else if (decoded is Map && decoded['id'] is String) {
          // Accept the single-package marker written by the first prototype.
          activePackages[package.component.value] = decoded;
        }
      } on FormatException {
        // A corrupt marker is replaced only after the package itself passed
        // verification above.
      }
    }
    activePackages[package.component.value] = package.toMap();
    final temporary = File('${marker.path}.part');
    await temporary.writeAsString(
      JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'profile': package.profile.value,
        'packages': activePackages,
      }),
    );
    if (await marker.exists()) {
      await marker.delete();
    }
    await temporary.rename(marker.path);
  }

  Future<void> remove(ModelPackage package) async {
    final file = await fileFor(package);
    if (await file.exists()) {
      await file.delete();
    }
    final root = await _root();
    final marker = File(
      path.join(root.path, 'active-${package.profile.value}.json'),
    );
    if (!await marker.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is Map && decoded['packages'] is Map) {
        final packages = Map<String, Object?>.from(
          (decoded['packages'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        final selected = packages[package.component.value];
        if (selected is Map &&
            selected['id'] == package.id &&
            selected['version'] == package.version &&
            selected['sha256'] == package.sha256) {
          packages.remove(package.component.value);
        }
        if (packages.isEmpty) {
          await marker.delete();
        } else {
          await marker.writeAsString(
            JsonEncoder.withIndent('  ').convert(<String, Object?>{
              'profile': package.profile.value,
              'packages': packages,
            }),
          );
        }
      } else {
        await marker.delete();
      }
    } on FormatException {
      await marker.delete();
    }
  }

  /// Returns verified catalog entries currently selected for a profile.
  Future<List<ModelPackage>> activePackages(
    CapabilityProfile profile,
    Iterable<ModelPackage> catalog,
  ) async {
    final root = await _root();
    final marker = File(path.join(root.path, 'active-${profile.value}.json'));
    if (!await marker.exists()) {
      return const <ModelPackage>[];
    }
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map || decoded['packages'] is! Map) {
        return const <ModelPackage>[];
      }
      final selected = <ModelPackage>[];
      for (final entry in (decoded['packages'] as Map).entries) {
        final value = entry.value;
        if (value is! Map || value['id'] is! String) {
          continue;
        }
        for (final candidate in catalog) {
          if (candidate.profile == profile &&
              candidate.id == value['id'] &&
              candidate.component.value == entry.key &&
              candidate.version == value['version'] &&
              candidate.sha256.toLowerCase() ==
                  (value['sha256'] as String? ?? '').toLowerCase() &&
              (await verify(candidate)).ready) {
            selected.add(candidate);
            break;
          }
        }
      }
      return selected;
    } on FormatException {
      return const <ModelPackage>[];
    }
  }

  Future<bool> isProfileReady(
    CapabilityProfile profile,
    Iterable<ModelPackage> catalog,
  ) async {
    final required = catalog.where((package) => package.profile == profile);
    if (ModelComponent.values.any(
      (component) => !required.any((package) => package.component == component),
    )) {
      return false;
    }
    final active = await activePackages(profile, required);
    return ModelComponent.values.every(
      (component) => active.any(
        (selected) => selected.component == component,
      ),
    );
  }

  Future<void> writeManifest(List<ModelPackage> packages) async {
    final root = await _root();
    await root.create(recursive: true);
    final manifest = File(path.join(root.path, 'manifest.json'));
    final encoded = JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'packages': packages.map((package) => package.toMap()).toList(),
    });
    final temporary = File('${manifest.path}.part');
    try {
      await temporary.writeAsString(encoded);
      if (await manifest.exists()) {
        await manifest.delete();
      }
      await temporary.rename(manifest.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<List<ModelPackage>> readManifest() async {
    final root = await _root();
    final manifest = File(path.join(root.path, 'manifest.json'));
    if (!await manifest.exists()) {
      return const <ModelPackage>[];
    }
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map || decoded['packages'] is! List) {
      throw const FormatException('El manifiesto de modelos no es válido.');
    }
    return (decoded['packages'] as List).map((entry) {
      if (entry is! Map) {
        throw const FormatException('Una entrada del manifiesto no es válida.');
      }
      final map = <String, Object?>{};
      for (final item in entry.entries) {
        if (item.key is! String) {
          throw const FormatException('Una clave del manifiesto no es válida.');
        }
        map[item.key as String] = item.value;
      }
      return ModelPackage.fromMap(map);
    }).toList(growable: false);
  }
}

/// Catalog shape used by the installer UI. The URLs and hashes remain
/// placeholders until the Phase 1 spike selects immutable HTTPS artifacts.
List<ModelPackage> defaultModelCatalog() => <ModelPackage>[
      const ModelPackage(
        id: 'whisper-base-multilingual',
        profile: CapabilityProfile.basic,
        component: ModelComponent.speechRecognizer,
        version: 'pending-spike',
        fileName: 'ggml-base.bin',
        sha256: 'PENDING_SHA256',
        license: 'MIT',
        sizeBytes: 0,
        sourceUrl: 'https://github.com/ggml-org/whisper.cpp',
      ),
      const ModelPackage(
        id: 'qwen3.5-0.8b-q4',
        profile: CapabilityProfile.basic,
        component: ModelComponent.dialogue,
        version: 'pending-spike',
        fileName: 'qwen3.5-0.8b-q4.gguf',
        sha256: 'PENDING_SHA256',
        license: 'Apache-2.0',
        sizeBytes: 0,
        sourceUrl: 'https://huggingface.co/Qwen/Qwen3.5-0.8B',
      ),
      const ModelPackage(
        id: 'supertonic-3',
        profile: CapabilityProfile.basic,
        component: ModelComponent.speechSynthesizer,
        version: 'pending-spike',
        fileName: 'supertonic-3.onnx',
        sha256: 'PENDING_SHA256',
        license: 'OpenRAIL-M',
        sizeBytes: 0,
        sourceUrl: 'https://huggingface.co/Supertone/supertonic-3',
      ),
      const ModelPackage(
        id: 'qwen3.5-4b-q4',
        profile: CapabilityProfile.advanced,
        component: ModelComponent.dialogue,
        version: 'pending-spike',
        fileName: 'qwen3.5-4b-q4.gguf',
        sha256: 'PENDING_SHA256',
        license: 'Apache-2.0',
        sizeBytes: 0,
        sourceUrl: 'https://huggingface.co/Qwen/Qwen3.5-4B',
      ),
    ];
