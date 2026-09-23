import 'dart:async';

import 'package:flutter/material.dart';

import 'services/model_manager.dart';
import 'services/platform_settings.dart';

/// Installs verified model bytes in the app-private support directory.
class ModelDownloadSection extends StatefulWidget {
  const ModelDownloadSection({
    required this.manager,
    super.key,
  });

  final ModelManager manager;

  @override
  State<ModelDownloadSection> createState() => _ModelDownloadSectionState();
}

class _ModelDownloadSectionState extends State<ModelDownloadSection>
    with WidgetsBindingObserver {
  late final List<ModelPackage> _packages = defaultModelCatalog()
      .where(
        (package) =>
            package.profile == CapabilityProfile.basic && package.isImmutable,
      )
      .toList(growable: false);
  late final ModelBundle _ttsBundle =
      supertonic3Bundle(CapabilityProfile.basic);

  final Map<String, ModelVerification> _packageVerification =
      <String, ModelVerification>{};
  final Map<String, _DownloadProgress> _progress =
      <String, _DownloadProgress>{};
  final Map<String, String> _errors = <String, String>{};
  final Set<String> _busy = <String>{};
  final Map<String, ModelDownloadCancellation> _cancellations =
      <String, ModelDownloadCancellation>{};
  final Map<String, int> _bundleReceived = <String, int>{};

  ModelBundleVerification? _bundleVerification;
  Set<String> _activePackageIds = <String>{};
  bool _bundleActive = false;
  bool _loading = true;
  bool _backgroundNotice = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _cancellations.isNotEmpty) {
      if (mounted) {
        setState(() => _backgroundNotice = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Modelos locales',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Descarga los pesos una vez para usar STT, diálogo y voz sin conexión.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.download_for_offline_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Preparación offline',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar estado',
                      onPressed: _loading ? null : () => unawaited(_refresh()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Se valida tamaño y SHA-256 antes de activar cada archivo. '
                  'Se recomienda usar Wi-Fi y tener espacio libre suficiente.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_backgroundNotice) ...<Widget>[
                  const SizedBox(height: 12),
                  _BackgroundNotice(onOpenSettings: _openBackgroundSettings),
                ],
                if (_loadError != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _ErrorMessage(message: _loadError!),
                ],
                if (_loading) ...<Widget>[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 8),
                ..._packages.map(_buildPackageTile),
                _buildBundleTile(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPackageTile(ModelPackage package) {
    final verification = _packageVerification[package.id];
    final active = _activePackageIds.contains(package.id);
    final busy = _busy.contains(package.id);
    return _ModelTile(
      icon: _packageIcon(package),
      title: _packageTitle(package),
      subtitle:
          '${_formatBytes(package.sizeBytes)} · ${_packageStatus(verification, active)}',
      progress: _progress[package.id],
      error: _errors[package.id],
      onRemove: verification?.installed == true && !busy
          ? () => unawaited(_removePackage(package))
          : null,
      action: _actionButton(
        busy: busy,
        cancellable: _cancellations.containsKey(package.id),
        ready: verification?.ready == true,
        active: active,
        onDownload: () => unawaited(_downloadPackage(package)),
        onActivate: () => unawaited(_activatePackage(package)),
        onCancel: () => _cancel(package.id),
      ),
    );
  }

  Widget _buildBundleTile() {
    final verification = _bundleVerification;
    final busy = _busy.contains(_ttsBundle.id);
    final installed =
        verification?.artifacts.any((artifact) => artifact.installed) == true;
    final status = verification == null
        ? 'Comprobando estado'
        : verification.ready
            ? _bundleActive
                ? 'Activo'
                : 'Listo para activar'
            : installed
                ? 'Instalado, pero necesita verificación'
                : 'No descargado';

    return _ModelTile(
      icon: Icons.record_voice_over_outlined,
      title: 'Voz · Supertonic 3 (M1)',
      subtitle: '${_formatBytes(_ttsBundle.sizeBytes)} · $status',
      progress: _progress[_ttsBundle.id],
      error: _errors[_ttsBundle.id],
      onRemove: installed && !busy ? () => unawaited(_removeBundle()) : null,
      action: _actionButton(
        busy: busy,
        cancellable: _cancellations.containsKey(_ttsBundle.id),
        ready: verification?.ready == true,
        active: _bundleActive,
        onDownload: () => unawaited(_downloadBundle()),
        onActivate: () => unawaited(_activateBundle()),
        onCancel: () => _cancel(_ttsBundle.id),
      ),
    );
  }

  Widget _actionButton({
    required bool busy,
    required bool cancellable,
    required bool ready,
    required bool active,
    required VoidCallback onDownload,
    required VoidCallback onActivate,
    required VoidCallback onCancel,
  }) {
    const actionWidth = 132.0;
    if (busy) {
      return SizedBox(
        width: actionWidth,
        child: OutlinedButton(
          onPressed: cancellable ? onCancel : null,
          child: _buttonLabel(cancellable ? 'Cancelar' : 'Procesando'),
        ),
      );
    }
    if (ready && active) {
      return SizedBox(
        width: actionWidth,
        child: OutlinedButton(
          onPressed: null,
          child: _buttonLabel('Activo'),
        ),
      );
    }
    if (ready) {
      return SizedBox(
        width: actionWidth,
        child: FilledButton(
          onPressed: onActivate,
          child: _buttonLabel('Activar'),
        ),
      );
    }
    return SizedBox(
      width: actionWidth,
      child: FilledButton(
        onPressed: onDownload,
        child: _buttonLabel('Descargar'),
      ),
    );
  }

  Widget _buttonLabel(String label) => Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );

  Future<void> _downloadPackage(ModelPackage package) async {
    if (_busy.contains(package.id)) {
      return;
    }
    final cancellation = _begin(
      package.id,
      package.sizeBytes,
      cancellable: true,
    );
    try {
      final verification = await widget.manager.download(
        package,
        cancellation: cancellation,
        onProgress: (receivedBytes, totalBytes) {
          _updateProgress(package.id, receivedBytes, totalBytes);
        },
      );
      await widget.manager.activate(package);
      _showRestartHint(_packageTitle(package));
      if (mounted) {
        setState(() {
          _packageVerification[package.id] = verification;
          _activePackageIds = <String>{..._activePackageIds, package.id};
        });
      }
    } catch (error) {
      _setError(package.id, error);
    } finally {
      await _finish(package.id);
    }
  }

  Future<void> _activatePackage(ModelPackage package) async {
    if (_busy.contains(package.id)) {
      return;
    }
    _begin(package.id, package.sizeBytes);
    try {
      await widget.manager.activate(package);
      _showRestartHint(_packageTitle(package));
    } catch (error) {
      _setError(package.id, error);
    } finally {
      await _finish(package.id);
    }
  }

  Future<void> _removePackage(ModelPackage package) async {
    if (!await _confirmRemoval(package.fileName)) {
      return;
    }
    _begin(package.id, package.sizeBytes);
    try {
      await widget.manager.remove(package);
    } catch (error) {
      _setError(package.id, error);
    } finally {
      await _finish(package.id);
    }
  }

  Future<void> _downloadBundle() async {
    if (_busy.contains(_ttsBundle.id)) {
      return;
    }
    _bundleReceived.clear();
    final cancellation = _begin(
      _ttsBundle.id,
      _ttsBundle.sizeBytes,
      cancellable: true,
    );
    try {
      final verification = await widget.manager.downloadBundle(
        _ttsBundle,
        cancellation: cancellation,
        onProgress: (artifactId, receivedBytes, totalBytes) {
          _bundleReceived[artifactId] = receivedBytes;
          final received = _ttsBundle.artifacts.fold<int>(
            0,
            (sum, artifact) => sum + (_bundleReceived[artifact.id] ?? 0),
          );
          _updateProgress(_ttsBundle.id, received, _ttsBundle.sizeBytes);
        },
      );
      await widget.manager.activateBundle(_ttsBundle);
      _showRestartHint('Supertonic 3');
      if (mounted) {
        setState(() {
          _bundleVerification = verification;
          _bundleActive = true;
        });
      }
    } catch (error) {
      _setError(_ttsBundle.id, error);
    } finally {
      await _finish(_ttsBundle.id);
    }
  }

  Future<void> _activateBundle() async {
    if (_busy.contains(_ttsBundle.id)) {
      return;
    }
    _begin(_ttsBundle.id, _ttsBundle.sizeBytes);
    try {
      await widget.manager.activateBundle(_ttsBundle);
      _showRestartHint('Supertonic 3');
      if (mounted) {
        setState(() => _bundleActive = true);
      }
    } catch (error) {
      _setError(_ttsBundle.id, error);
    } finally {
      await _finish(_ttsBundle.id);
    }
  }

  Future<void> _removeBundle() async {
    if (!await _confirmRemoval('Supertonic 3')) {
      return;
    }
    _begin(_ttsBundle.id, _ttsBundle.sizeBytes);
    try {
      await widget.manager.removeBundle(_ttsBundle);
    } catch (error) {
      _setError(_ttsBundle.id, error);
    } finally {
      await _finish(_ttsBundle.id);
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final packageVerification = <String, ModelVerification>{};
      for (final package in _packages) {
        packageVerification[package.id] = await widget.manager.verify(package);
      }
      final activePackages = await widget.manager.activePackages(
        CapabilityProfile.basic,
        _packages,
      );
      final bundleVerification = await widget.manager.verifyBundle(_ttsBundle);
      final activeBundles = await widget.manager.activeBundles(
        CapabilityProfile.basic,
        <ModelBundle>[_ttsBundle],
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _packageVerification
          ..clear()
          ..addAll(packageVerification);
        _activePackageIds = activePackages.map((package) => package.id).toSet();
        _bundleVerification = bundleVerification;
        _bundleActive = activeBundles.isNotEmpty;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = 'No se pudo leer el estado local: $error';
      });
    }
  }

  Future<void> _openBackgroundSettings() async {
    final opened = await PlatformSettings.openBackgroundSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Abre Ajustes de Android → Aplicaciones → LearnIt → Batería '
            'y selecciona “Sin restricciones”.',
          ),
        ),
      );
    }
  }

  ModelDownloadCancellation? _begin(
    String id,
    int totalBytes, {
    bool cancellable = false,
  }) {
    if (!mounted) {
      return null;
    }
    final cancellation = cancellable ? ModelDownloadCancellation() : null;
    setState(() {
      _busy.add(id);
      if (cancellation != null) {
        _cancellations[id] = cancellation;
      }
      _errors.remove(id);
      _progress[id] = _DownloadProgress(
        receivedBytes: 0,
        totalBytes: totalBytes,
      );
    });
    return cancellation;
  }

  void _cancel(String id) {
    _cancellations[id]?.cancel();
  }

  void _updateProgress(String id, int receivedBytes, int totalBytes) {
    if (!mounted) {
      return;
    }
    setState(() {
      _progress[id] = _DownloadProgress(
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
      );
    });
  }

  void _setError(String id, Object error) {
    if (!mounted) {
      return;
    }
    setState(() => _errors[id] = _friendlyError(error));
  }

  void _showRestartHint(String modelName) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('$modelName activado. Reinicia la aplicación para usarlo.'),
      ),
    );
  }

  Future<void> _finish(String id) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy.remove(id);
      _cancellations.remove(id);
      _progress.remove(id);
    });
    await _refresh();
  }

  Future<bool> _confirmRemoval(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar pesos locales'),
        content: Text('¿Quieres eliminar los archivos de $name?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  String _packageTitle(ModelPackage package) {
    switch (package.component) {
      case ModelComponent.speechRecognizer:
        return 'Reconocimiento · Whisper base';
      case ModelComponent.dialogue:
        return 'Diálogo · Qwen3.5 0.8B';
      case ModelComponent.speechSynthesizer:
        return package.fileName;
    }
  }

  IconData _packageIcon(ModelPackage package) {
    switch (package.component) {
      case ModelComponent.speechRecognizer:
        return Icons.graphic_eq;
      case ModelComponent.dialogue:
        return Icons.chat_bubble_outline;
      case ModelComponent.speechSynthesizer:
        return Icons.record_voice_over_outlined;
    }
  }

  String _packageStatus(ModelVerification? verification, bool active) {
    if (verification == null) {
      return 'Comprobando estado';
    }
    if (verification.ready) {
      return active ? 'Activo' : 'Listo para activar';
    }
    if (verification.installed) {
      return 'Instalado, pero necesita verificación';
    }
    return 'No descargado';
  }

  String _friendlyError(Object error) {
    if (error is ModelDownloadCancelled) {
      return 'Descarga cancelada. Puedes reanudarla cuando quieras.';
    }
    final text = error.toString();
    final lowerText = text.toLowerCase();
    if (lowerText.contains('connection closed') ||
        lowerText.contains('connection reset') ||
        lowerText.contains('timed out') ||
        lowerText.contains('connection abort')) {
      return 'La descarga se interrumpió al cambiar de aplicación. Activa '
          '“Permitir actividad en segundo plano” para LearnIt y pulsa '
          'Descargar otra vez; se conservará el avance parcial.';
    }
    if (text.length <= 180) {
      return text;
    }
    return '${text.substring(0, 177)}…';
  }
}

class _BackgroundNotice extends StatelessWidget {
  const _BackgroundNotice({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Actividad en segundo plano',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Para cambiar de aplicación mientras descargas o practicas, '
              'activa “Permitir actividad en segundo plano” para LearnIt. '
              'Las descargas interrumpidas se pueden reanudar.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Abrir ajustes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    this.progress,
    this.error,
    this.onRemove,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;
  final _DownloadProgress? progress;
  final String? error;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress!.fraction),
            const SizedBox(height: 4),
            Text(
              progress!.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (error != null) ...<Widget>[
            const SizedBox(height: 6),
            _ErrorMessage(message: error!),
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (onRemove != null)
                IconButton(
                  tooltip: 'Eliminar pesos',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              action,
            ],
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

class _DownloadProgress {
  const _DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double? get fraction {
    if (totalBytes <= 0) {
      return null;
    }
    return (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  String get label {
    if (totalBytes <= 0) {
      return _formatBytes(receivedBytes);
    }
    return '${_formatBytes(receivedBytes)} de ${_formatBytes(totalBytes)}';
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
