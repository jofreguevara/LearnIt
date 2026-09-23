import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum CapabilityProfile { basic, advanced }

enum ModelComponent { speechRecognizer, dialogue, speechSynthesizer }

final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');
final _revisionPattern = RegExp(r'^[a-fA-F0-9]{40,64}$');
final _bundleIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

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
    this.sourceRevision = '',
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

  /// Immutable upstream revision used to make the source URL reproducible.
  ///
  /// Older local manifests may omit this field; new downloadable catalog
  /// entries should always use a commit hash rather than a mutable branch or
  /// tag.
  final String sourceRevision;

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
    final immutable = immutableSourceError;
    if (immutable != null) {
      return immutable;
    }
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Los paquetes deben descargarse por HTTPS desde una URL válida.';
    }
    return null;
  }

  bool get isPinned => metadataError == null;

  /// Returns a validation message for a source that must not change beneath
  /// the installer. The revision is deliberately a full commit hash and the
  /// URL must address that revision directly.
  String? get immutableSourceError {
    final metadata = metadataError;
    if (metadata != null) {
      return metadata;
    }
    final revision = sourceRevision.trim();
    if (!_revisionPattern.hasMatch(revision)) {
      return 'El paquete $id necesita una revisión inmutable de 40 a 64 caracteres hexadecimales.';
    }
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Los paquetes deben descargarse por HTTPS desde una URL válida.';
    }
    if (!uri.path.contains('/resolve/$revision/')) {
      return 'La URL del paquete $id no está fijada a su revisión de origen.';
    }
    return null;
  }

  bool get isImmutable => immutableSourceError == null;

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
        'source_revision': sourceRevision,
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
    final revisionValue = map['source_revision'];
    if (revisionValue != null && revisionValue is! String) {
      throw const FormatException('La revisión del modelo no es texto.');
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
      sourceRevision: revisionValue as String? ?? '',
    );
  }
}

/// One file belonging to a logical model bundle, such as the ONNX graphs,
/// configuration and voice style required by Supertonic.
class ModelArtifact {
  const ModelArtifact({
    required this.id,
    required this.relativePath,
    required this.version,
    required this.sha256,
    required this.license,
    required this.sizeBytes,
    required this.sourceUrl,
    required this.sourceRevision,
  });

  final String id;
  final String relativePath;
  final String version;
  final String sha256;
  final String license;
  final int sizeBytes;
  final String sourceUrl;
  final String sourceRevision;

  String? get metadataError {
    if (id.trim().isEmpty) {
      return 'El artefacto debe tener un identificador.';
    }
    if (version.trim().isEmpty) {
      return 'El artefacto $id necesita una versión fijada.';
    }
    final segments = relativePath.split(RegExp(r'[/\\]'));
    if (relativePath.trim().isEmpty ||
        path.isAbsolute(relativePath) ||
        segments.any((segment) =>
            segment.isEmpty || segment == '.' || segment == '..')) {
      return 'La ruta relativa del artefacto $id no es segura.';
    }
    if (!_sha256Pattern.hasMatch(sha256)) {
      return 'El artefacto $id necesita un SHA-256 hexadecimal de 64 caracteres.';
    }
    if (sizeBytes <= 0) {
      return 'El artefacto $id necesita un tamaño instalado positivo.';
    }
    if (license.trim().isEmpty) {
      return 'El artefacto $id necesita declarar su licencia.';
    }
    return null;
  }

  String? get immutableSourceError {
    final metadata = metadataError;
    if (metadata != null) {
      return metadata;
    }
    if (!_revisionPattern.hasMatch(sourceRevision)) {
      return 'El artefacto $id necesita una revisión inmutable hexadecimal.';
    }
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Los artefactos deben descargarse por HTTPS desde una URL válida.';
    }
    if (!uri.path.contains('/resolve/$sourceRevision/')) {
      return 'La URL del artefacto $id no está fijada a su revisión de origen.';
    }
    return null;
  }

  bool get isImmutable => immutableSourceError == null;

  Map<String, Object?> toMap() => {
        'id': id,
        'relative_path': relativePath,
        'version': version,
        'sha256': sha256,
        'license': license,
        'size_bytes': sizeBytes,
        'source_url': sourceUrl,
        'source_revision': sourceRevision,
      };

  factory ModelArtifact.fromMap(Map<String, Object?> map) {
    final sizeValue = map['size_bytes'];
    if (sizeValue is! num) {
      throw const FormatException('El tamaño del artefacto no es numérico.');
    }
    return ModelArtifact(
      id: _requiredString(map, 'id'),
      relativePath: _requiredString(map, 'relative_path'),
      version: _requiredString(map, 'version'),
      sha256: _requiredString(map, 'sha256'),
      license: _requiredString(map, 'license'),
      sizeBytes: sizeValue.toInt(),
      sourceUrl: _requiredString(map, 'source_url'),
      sourceRevision: _requiredString(map, 'source_revision'),
    );
  }
}

/// A logical model made up of multiple verified files.
class ModelBundle {
  const ModelBundle({
    required this.id,
    required this.profile,
    required this.component,
    required this.version,
    required this.artifacts,
  });

  final String id;
  final CapabilityProfile profile;
  final ModelComponent component;
  final String version;
  final List<ModelArtifact> artifacts;

  int get sizeBytes => artifacts.fold<int>(
        0,
        (total, artifact) => total + artifact.sizeBytes,
      );

  String? get metadataError {
    if (!_bundleIdPattern.hasMatch(id)) {
      return 'El bundle necesita un identificador seguro.';
    }
    if (version.trim().isEmpty) {
      return 'El bundle $id necesita una versión fijada.';
    }
    if (artifacts.isEmpty) {
      return 'El bundle $id debe contener al menos un artefacto.';
    }
    final ids = <String>{};
    final paths = <String>{};
    for (final artifact in artifacts) {
      if (!ids.add(artifact.id)) {
        return 'El bundle $id contiene el artefacto duplicado ${artifact.id}.';
      }
      if (!paths.add(artifact.relativePath)) {
        return 'El bundle $id contiene la ruta duplicada ${artifact.relativePath}.';
      }
      final error = artifact.metadataError;
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? get immutableSourceError {
    final metadata = metadataError;
    if (metadata != null) {
      return metadata;
    }
    for (final artifact in artifacts) {
      final error = artifact.immutableSourceError;
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  bool get isImmutable => immutableSourceError == null;

  Map<String, Object?> toMap() => {
        'id': id,
        'profile': profile.value,
        'component': component.value,
        'version': version,
        'artifacts': artifacts.map((artifact) => artifact.toMap()).toList(),
      };

  factory ModelBundle.fromMap(Map<String, Object?> map) {
    final profileValue = map['profile'];
    final profile = CapabilityProfile.values
        .where((candidate) => candidate.value == profileValue)
        .firstOrNull;
    if (profile == null) {
      throw const FormatException('Perfil de bundle desconocido.');
    }
    final componentValue = map['component'];
    final component = ModelComponent.values
        .where((candidate) => candidate.value == componentValue)
        .firstOrNull;
    if (component == null) {
      throw const FormatException('Componente de bundle desconocido.');
    }
    final artifactValue = map['artifacts'];
    if (artifactValue is! List) {
      throw const FormatException(
          'Los artefactos del bundle no son una lista.');
    }
    final artifacts = artifactValue.map((entry) {
      if (entry is! Map) {
        throw const FormatException('Una entrada del bundle no es válida.');
      }
      final artifactMap = <String, Object?>{};
      for (final item in entry.entries) {
        if (item.key is! String) {
          throw const FormatException('Una clave de artefacto no es válida.');
        }
        artifactMap[item.key as String] = item.value;
      }
      return ModelArtifact.fromMap(artifactMap);
    }).toList(growable: false);
    return ModelBundle(
      id: _requiredString(map, 'id'),
      profile: profile,
      component: component,
      version: _requiredString(map, 'version'),
      artifacts: artifacts,
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

/// Cooperative cancellation for a model transfer. An interrupted transfer
/// keeps its `.part` file so the next attempt can resume with HTTP Range.
class ModelDownloadCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const ModelDownloadCancelled();
    }
  }
}

class ModelDownloadCancelled implements Exception {
  const ModelDownloadCancelled();

  @override
  String toString() => 'La descarga fue cancelada.';
}

class ModelArtifactVerification {
  const ModelArtifactVerification({
    required this.artifact,
    required this.installed,
    required this.hashMatches,
    this.sizeMatches = true,
    this.actualSizeBytes,
  });

  final ModelArtifact artifact;
  final bool installed;
  final bool hashMatches;
  final bool sizeMatches;
  final int? actualSizeBytes;

  bool get ready => installed && hashMatches && sizeMatches;
}

class ModelBundleVerification {
  const ModelBundleVerification({
    required this.bundle,
    required this.artifacts,
  });

  final ModelBundle bundle;
  final List<ModelArtifactVerification> artifacts;

  bool get ready =>
      artifacts.length == bundle.artifacts.length &&
      artifacts.every((artifact) => artifact.ready);
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest digest) => value = digest;

  @override
  void close() {}
}

class _DownloadResponse {
  const _DownloadResponse(this.response, this.uri);

  final HttpClientResponse response;
  final Uri uri;
}

/// Validates the catalog before it reaches an installer UI or a release
/// manifest. Duplicate IDs make activation ambiguous, while mutable sources
/// make an otherwise correct SHA-256 difficult to reproduce later.
List<String> validateModelCatalog(Iterable<ModelPackage> catalog) {
  final errors = <String>[];
  final ids = <String>{};
  for (final package in catalog) {
    if (!ids.add(package.id)) {
      errors.add(
          'El catálogo contiene el identificador duplicado ${package.id}.');
    }
    final metadata = package.metadataError;
    if (metadata != null) {
      errors.add(metadata);
      continue;
    }
    final source = package.immutableSourceError;
    if (source != null) {
      errors.add(source);
    }
  }
  return errors;
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

  Future<Directory> _bundleDirectory(ModelBundle bundle) async {
    final error = bundle.metadataError;
    if (error != null) {
      throw ArgumentError.value(bundle.id, 'bundle', error);
    }
    final root = await _root();
    final directory = Directory(
      path.join(root.path, bundle.profile.value, 'bundles', bundle.id),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> fileForArtifact(
    ModelBundle bundle,
    ModelArtifact artifact,
  ) async {
    final bundleArtifact = bundle.artifacts.where(
      (candidate) =>
          candidate.id == artifact.id &&
          candidate.relativePath == artifact.relativePath,
    );
    if (bundleArtifact.isEmpty) {
      throw ArgumentError.value(
        artifact.id,
        'artifact',
        'El artefacto no pertenece al bundle indicado.',
      );
    }
    final directory = await _bundleDirectory(bundle);
    final file = File(path.join(directory.path, artifact.relativePath));
    await file.parent.create(recursive: true);
    return file;
  }

  Future<ModelVerification> verify(ModelPackage package) async {
    final file = await fileFor(package);
    return _verifyFile(package, file);
  }

  /// Returns a model path only after the installed bytes pass the catalog
  /// size and SHA-256 checks. Native runtimes receive this path; they never
  /// resolve URLs or decide which package is trusted.
  Future<File> verifiedFileFor(ModelPackage package) async {
    final file = await fileFor(package);
    final verification = await _verifyFile(package, file);
    if (!verification.ready) {
      throw StateError(
        'El paquete ${package.id} no está instalado y verificado.',
      );
    }
    return file;
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

  Future<ModelArtifactVerification> _verifyArtifactFile(
    ModelArtifact artifact,
    File file,
  ) async {
    if (!await file.exists()) {
      return ModelArtifactVerification(
        artifact: artifact,
        installed: false,
        hashMatches: false,
      );
    }
    final digestSink = _DigestSink();
    final converter = sha256.startChunkedConversion(digestSink);
    await for (final chunk in file.openRead()) {
      converter.add(chunk);
    }
    converter.close();
    final actualHash = digestSink.value?.toString() ?? '';
    final actualSize = await file.length();
    return ModelArtifactVerification(
      artifact: artifact,
      installed: true,
      hashMatches: actualHash.toLowerCase() == artifact.sha256.toLowerCase(),
      sizeMatches: actualSize == artifact.sizeBytes,
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

  Future<ModelBundleVerification> verifyBundle(ModelBundle bundle) async {
    final error = bundle.metadataError;
    if (error != null) {
      throw StateError('El bundle no es válido: $error');
    }
    final results = <ModelArtifactVerification>[];
    for (final artifact in bundle.artifacts) {
      final file = await fileForArtifact(bundle, artifact);
      results.add(await _verifyArtifactFile(artifact, file));
    }
    return ModelBundleVerification(bundle: bundle, artifacts: results);
  }

  /// Returns a bundle directory only after every declared artifact passes its
  /// size and SHA-256 checks. Native runtimes never receive an unverified path.
  Future<Directory> verifiedBundleDirectory(ModelBundle bundle) async {
    final verification = await verifyBundle(bundle);
    if (!verification.ready) {
      throw StateError(
        'El bundle ${bundle.id} no está instalado y verificado.',
      );
    }
    return _bundleDirectory(bundle);
  }

  /// Imports all files into a staging directory and promotes the complete
  /// bundle only after every artifact passes its own SHA-256 and size check.
  Future<ModelBundleVerification> importBundle(
    ModelBundle bundle,
    Map<String, File> sources,
  ) async {
    final error = bundle.immutableSourceError;
    if (error != null) {
      throw StateError('El bundle no se puede instalar: $error');
    }
    final root = await _root();
    final destination = Directory(
      path.join(root.path, bundle.profile.value, 'bundles', bundle.id),
    );
    await destination.parent.create(recursive: true);
    final staging = Directory('${destination.path}.part');
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);
    var promoted = false;
    try {
      for (final artifact in bundle.artifacts) {
        final source = sources[artifact.id];
        if (source == null || !await source.exists()) {
          throw ArgumentError.value(
            artifact.id,
            'sources',
            'Falta el archivo fuente del artefacto.',
          );
        }
        final stagedFile = File(path.join(staging.path, artifact.relativePath));
        await stagedFile.parent.create(recursive: true);
        await source.copy(stagedFile.path);
        final verification = await _verifyArtifactFile(artifact, stagedFile);
        if (!verification.ready) {
          throw StateError(
            'El artefacto ${artifact.id} no supera la verificación.',
          );
        }
      }

      await _promoteBundle(staging, destination);
      promoted = true;
      return await verifyBundle(bundle);
    } finally {
      if (!promoted && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  ModelPackage _packageForArtifact(
    ModelBundle bundle,
    ModelArtifact artifact,
  ) {
    return ModelPackage(
      id: '${bundle.id}:${artifact.id}',
      profile: bundle.profile,
      component: bundle.component,
      version: artifact.version,
      fileName: path.basename(artifact.relativePath),
      sha256: artifact.sha256,
      license: artifact.license,
      sizeBytes: artifact.sizeBytes,
      sourceUrl: artifact.sourceUrl,
      sourceRevision: artifact.sourceRevision,
    );
  }

  Future<void> _promoteBundle(
    Directory staging,
    Directory destination,
  ) async {
    final previous = Directory('${destination.path}.previous');
    if (await previous.exists()) {
      await previous.delete(recursive: true);
    }
    var movedPrevious = false;
    try {
      if (await destination.exists()) {
        await destination.rename(previous.path);
        movedPrevious = true;
      }
      await staging.rename(destination.path);
      if (movedPrevious && await previous.exists()) {
        await previous.delete(recursive: true);
      }
    } catch (_) {
      if (movedPrevious &&
          !await destination.exists() &&
          await previous.exists()) {
        await previous.rename(destination.path);
      }
      rethrow;
    }
  }

  Future<ModelVerification> download(
    ModelPackage package, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
    ModelDownloadCancellation? cancellation,
  }) async {
    final destination = await fileFor(package);
    return _downloadTo(
      package,
      destination,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  Future<ModelBundleVerification> downloadBundle(
    ModelBundle bundle, {
    void Function(
      String artifactId,
      int receivedBytes,
      int totalBytes,
    )? onProgress,
    ModelDownloadCancellation? cancellation,
  }) async {
    final error = bundle.immutableSourceError;
    if (error != null) {
      throw ArgumentError.value(bundle.id, 'bundle', error);
    }
    final root = await _root();
    final destination = Directory(
      path.join(root.path, bundle.profile.value, 'bundles', bundle.id),
    );
    await destination.parent.create(recursive: true);
    final staging = Directory('${destination.path}.part');
    await staging.create(recursive: true);
    for (final artifact in bundle.artifacts) {
      cancellation?.throwIfCancelled();
      final package = _packageForArtifact(bundle, artifact);
      final stagedFile = File(path.join(staging.path, artifact.relativePath));
      await stagedFile.parent.create(recursive: true);
      final installed = await _verifyArtifactFile(artifact, stagedFile);
      if (installed.ready) {
        onProgress?.call(
          artifact.id,
          artifact.sizeBytes,
          artifact.sizeBytes,
        );
        continue;
      }
      await _downloadTo(
        package,
        stagedFile,
        onProgress: (receivedBytes, totalBytes) {
          onProgress?.call(artifact.id, receivedBytes, totalBytes);
        },
        cancellation: cancellation,
      );
    }
    cancellation?.throwIfCancelled();
    await _promoteBundle(staging, destination);
    return await verifyBundle(bundle);
  }

  Future<ModelVerification> _downloadTo(
    ModelPackage package,
    File destination, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
    ModelDownloadCancellation? cancellation,
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
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    final client = HttpClient();
    var transferCompleted = false;
    try {
      cancellation?.throwIfCancelled();
      final existingBytes =
          await temporary.exists() ? await temporary.length() : 0;
      final opened = await _openDownloadResponse(
        client,
        uri,
        existingBytes: existingBytes,
      );
      final response = opened.response;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Descarga fallida (${response.statusCode}).',
            uri: opened.uri);
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
          cancellation?.throwIfCancelled();
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }
      } finally {
        await sink.close();
      }
      cancellation?.throwIfCancelled();
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

  Future<_DownloadResponse> _openDownloadResponse(
    HttpClient client,
    Uri initialUri, {
    required int existingBytes,
  }) async {
    var uri = initialUri;
    for (var redirect = 0; redirect < 6; redirect++) {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }
      final response = await request.close();
      if (<int>{301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || location.trim().isEmpty) {
          throw HttpException('La redirección no tiene destino.', uri: uri);
        }
        final redirected = uri.resolve(location);
        if (redirected.scheme != 'https' || redirected.host.isEmpty) {
          throw HttpException(
            'La descarga solo permite redirecciones HTTPS.',
            uri: redirected,
          );
        }
        uri = redirected;
        continue;
      }
      return _DownloadResponse(response, uri);
    }
    throw HttpException(
      'La descarga superó el máximo de redirecciones permitido.',
      uri: uri,
    );
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

  Future<void> activateBundle(ModelBundle bundle) async {
    final error = bundle.immutableSourceError;
    if (error != null) {
      throw StateError('No se puede activar el bundle: $error');
    }
    final verification = await verifyBundle(bundle);
    if (!verification.ready) {
      throw StateError(
        'El bundle ${bundle.id} no está instalado y verificado.',
      );
    }
    final root = await _root();
    final marker = File(
      path.join(root.path, 'active-${bundle.profile.value}.bundles.json'),
    );
    final activeBundles = <String, Object?>{};
    if (await marker.exists()) {
      try {
        final decoded = jsonDecode(await marker.readAsString());
        if (decoded is Map && decoded['bundles'] is Map) {
          activeBundles.addAll(
            (decoded['bundles'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
        }
      } on FormatException {
        // A corrupt marker is replaced only after the bundle passed
        // verification above.
      }
    }
    activeBundles[bundle.component.value] = bundle.toMap();
    final temporary = File('${marker.path}.part');
    await temporary.writeAsString(
      JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'profile': bundle.profile.value,
        'bundles': activeBundles,
      }),
    );
    if (await marker.exists()) {
      await marker.delete();
    }
    await temporary.rename(marker.path);
  }

  Future<List<ModelBundle>> activeBundles(
    CapabilityProfile profile,
    Iterable<ModelBundle> catalog,
  ) async {
    final root = await _root();
    final marker = File(
      path.join(root.path, 'active-${profile.value}.bundles.json'),
    );
    if (!await marker.exists()) {
      return const <ModelBundle>[];
    }
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map || decoded['bundles'] is! Map) {
        return const <ModelBundle>[];
      }
      final selected = <ModelBundle>[];
      for (final entry in (decoded['bundles'] as Map).entries) {
        final value = entry.value;
        if (value is! Map || value['id'] is! String) {
          continue;
        }
        for (final candidate in catalog) {
          if (candidate.profile == profile &&
              candidate.id == value['id'] &&
              candidate.component.value == entry.key &&
              candidate.version == value['version'] &&
              (await verifyBundle(candidate)).ready) {
            selected.add(candidate);
            break;
          }
        }
      }
      return selected;
    } on FormatException {
      return const <ModelBundle>[];
    }
  }

  Future<void> removeBundle(ModelBundle bundle) async {
    final root = await _root();
    final directory = Directory(
      path.join(root.path, bundle.profile.value, 'bundles', bundle.id),
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    final marker = File(
      path.join(root.path, 'active-${bundle.profile.value}.bundles.json'),
    );
    if (!await marker.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is Map && decoded['bundles'] is Map) {
        final bundles = Map<String, Object?>.from(
          (decoded['bundles'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        final selected = bundles[bundle.component.value];
        if (selected is Map &&
            selected['id'] == bundle.id &&
            selected['version'] == bundle.version) {
          bundles.remove(bundle.component.value);
        }
        if (bundles.isEmpty) {
          await marker.delete();
        } else {
          await marker.writeAsString(
            JsonEncoder.withIndent('  ').convert(<String, Object?>{
              'profile': bundle.profile.value,
              'bundles': bundles,
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

  Future<bool> isProfileReadyWithBundles(
    CapabilityProfile profile,
    Iterable<ModelPackage> packageCatalog,
    Iterable<ModelBundle> bundleCatalog,
  ) async {
    final requiredPackages = packageCatalog.where(
      (package) =>
          package.profile == profile &&
          package.component != ModelComponent.speechSynthesizer,
    );
    final selectedPackages = await activePackages(
      profile,
      requiredPackages,
    );
    final selectedBundles = await activeBundles(
      profile,
      bundleCatalog.where(
        (bundle) => bundle.component == ModelComponent.speechSynthesizer,
      ),
    );
    return ModelComponent.values.every((component) {
      if (component == ModelComponent.speechSynthesizer) {
        return selectedBundles.any((bundle) => bundle.component == component);
      }
      return selectedPackages.any((package) => package.component == component);
    });
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

/// Catalog shape used by the installer UI. The STT and basic LLM candidates
/// are pinned to immutable upstream commits. Supertonic is represented by
/// [supertonic3Bundle] because its ONNX graphs and voice style must activate
/// together rather than through the one-file package API.
List<ModelPackage> defaultModelCatalog() => <ModelPackage>[
      const ModelPackage(
        id: 'whisper-base-multilingual-q5_1',
        profile: CapabilityProfile.basic,
        component: ModelComponent.speechRecognizer,
        version: '5359861c739e955e79d9a303bcbc70fb988958b1',
        fileName: 'ggml-base-q5_1.bin',
        sha256:
            '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
        license: 'MIT',
        sizeBytes: 59707625,
        sourceUrl:
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base-q5_1.bin',
        sourceRevision: '5359861c739e955e79d9a303bcbc70fb988958b1',
      ),
      const ModelPackage(
        id: 'qwen3.5-0.8b-q4_0',
        profile: CapabilityProfile.basic,
        component: ModelComponent.dialogue,
        version: '8fea620810c4afa23dd6443f999a48574c1611a3',
        fileName: 'Qwen3.5-0.8B-Q4_0.gguf',
        sha256:
            '57d1997790d1744fba5b40a7317df71ea5e2acee28c47e78f0cce39c0703f8cf',
        license: 'Apache-2.0',
        sizeBytes: 563036064,
        sourceUrl:
            'https://huggingface.co/ggml-org/Qwen3.5-0.8B-GGUF/resolve/8fea620810c4afa23dd6443f999a48574c1611a3/Qwen3.5-0.8B-Q4_0.gguf',
        sourceRevision: '8fea620810c4afa23dd6443f999a48574c1611a3',
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

const _supertonic3Revision = 'aafc6e32416a594460b32413efc49d7fe4ce6d46';

/// Exact Supertonic 3 bundle used by the v0.7.1 local model installer.
///
/// The bundle deliberately lives outside [defaultModelCatalog] because a
/// [ModelPackage] represents one file while this runtime needs all seven
/// files together.
ModelBundle supertonic3Bundle(CapabilityProfile profile) => ModelBundle(
      id: 'supertonic-3',
      profile: profile,
      component: ModelComponent.speechSynthesizer,
      version: _supertonic3Revision,
      artifacts: const <ModelArtifact>[
        ModelArtifact(
          id: 'duration-predictor',
          relativePath: 'onnx/duration_predictor.onnx',
          version: _supertonic3Revision,
          sha256:
              'c3eb91414d5ff8a7a239b7fe9e34e7e2bf8a8140d8375ffb14718b1c639325db',
          license: 'OpenRAIL-M',
          sizeBytes: 3700147,
          sourceUrl:
              'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/aafc6e32416a594460b32413efc49d7fe4ce6d46/onnx/duration_predictor.onnx',
          sourceRevision: _supertonic3Revision,
        ),
        ModelArtifact(
          id: 'text-encoder',
          relativePath: 'onnx/text_encoder.onnx',
          version: _supertonic3Revision,
          sha256:
              'c7befd5ea8c3119769e8a6c1486c4edc6a3bc8365c67621c881bbb774b9902ff',
          license: 'OpenRAIL-M',
          sizeBytes: 36416150,
          sourceUrl:
              'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/aafc6e32416a594460b32413efc49d7fe4ce6d46/onnx/text_encoder.onnx',
          sourceRevision: _supertonic3Revision,
        ),
        ModelArtifact(
          id: 'vector-estimator',
          relativePath: 'onnx/vector_estimator.onnx',
          version: _supertonic3Revision,
          sha256:
              '883ac868ea0275ef0e991524dc64f16b3c0376efd7c320af6b53f5b780d7c61c',
          license: 'OpenRAIL-M',
          sizeBytes: 256534781,
          sourceUrl:
              'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/aafc6e32416a594460b32413efc49d7fe4ce6d46/onnx/vector_estimator.onnx',
          sourceRevision: _supertonic3Revision,
        ),
        ModelArtifact(
          id: 'vocoder',
          relativePath: 'onnx/vocoder.onnx',
          version: _supertonic3Revision,
          sha256:
              '085de76dd8e8d5836d6ca66826601f615939218f90e519f70ee8a36ed2a4c4ba',
          license: 'OpenRAIL-M',
          sizeBytes: 101424195,
          sourceUrl:
              'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/aafc6e32416a594460b32413efc49d7fe4ce6d46/onnx/vocoder.onnx',
          sourceRevision: _supertonic3Revision,
        ),
        ModelArtifact(
          id: 'tts-config',
          relativePath: 'onnx/tts.json',
          version: _supertonic3Revision,
          sha256:
              '42078d3aef1cd43ab43021f3c54f47d2d75ceb4e75f627f118890128b06a0d09',
          license: 'OpenRAIL-M',
          sizeBytes: 8253,
          sourceUrl:
              'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/aafc6e32416a594460b32413efc49d7fe4ce6d46/onnx/tts.json',
          sourceRevision: _supertonic3Revision,
        ),
        ModelArtifact(
          id: 'unicode-indexer',
          relativePath: 'onnx/unicode_indexer.json',
          version: _supertonic3Revision,
          sha256:
              '9bf7346e43883a81f8645c81224f786d43c5b57f3641f6e7671a7d6c493cb24f',
          license: 'OpenRAIL-M',
          sizeBytes: 277676,
          sourceUrl:
              'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/aafc6e32416a594460b32413efc49d7fe4ce6d46/onnx/unicode_indexer.json',
          sourceRevision: _supertonic3Revision,
        ),
        ModelArtifact(
          id: 'voice-m1',
          relativePath: 'voice_styles/M1.json',
          version: _supertonic3Revision,
          sha256:
              'e35604687f5d23694b8e91593a93eec0e4eca6c0b02bb8ed69139ab2ea6b0a5b',
          license: 'OpenRAIL-M',
          sizeBytes: 291748,
          sourceUrl:
              'https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/aafc6e32416a594460b32413efc49d7fe4ce6d46/voice_styles/M1.json',
          sourceRevision: _supertonic3Revision,
        ),
      ],
    );
