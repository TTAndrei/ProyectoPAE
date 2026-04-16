import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoLauncherApp());
}

class DemoLauncherApp extends StatelessWidget {
  const DemoLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lanzador Demo PAE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      ),
      home: const DemoLauncherPage(),
    );
  }
}

class DemoLauncherPage extends StatefulWidget {
  const DemoLauncherPage({super.key});

  @override
  State<DemoLauncherPage> createState() => _DemoLauncherPageState();
}

class _DemoLauncherPageState extends State<DemoLauncherPage> {
  bool _isBusy = false;
  bool _isRunning = false;
  bool _forceRestart = true;
  String _statusText = 'Listo para iniciar la demo';
  String _detailsText =
      'Pulsa Iniciar para lanzar backend + central + repartidor.';

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    final scripts = _resolveScripts();
    if (scripts == null) {
      setState(() {
        _isRunning = false;
        _statusText = 'No se encontraron scripts';
        _detailsText = 'No fue posible ubicar scripts/start-demo.ps1';
      });
      return;
    }

    final running = await scripts.stateFile.exists();
    setState(() {
      _isRunning = running;
      _statusText = running ? 'Demo en ejecucion' : 'Demo detenida';
      _detailsText = running
          ? 'Hay una sesion activa.'
          : 'Pulsa Iniciar para lanzar backend + central + repartidor.';
    });
  }

  _ResolvedScripts? _resolveScripts() {
    if (!Platform.isWindows) {
      return null;
    }

    final cwd = Directory.current.absolute.path;
    final candidates = <String>{
      cwd,
      _resolveRelative(cwd, '../'),
      _resolveRelative(cwd, '../../'),
      _resolveRelative(cwd, '../../../'),
      _resolveRelative(cwd, '../../../../'),
    };

    for (final base in candidates) {
      final direct = _tryBuildScripts(base, '');
      if (direct != null) {
        return direct;
      }

      final nested = _tryBuildScripts(base, 'ProyectoPAE/');
      if (nested != null) {
        return nested;
      }
    }

    return null;
  }

  _ResolvedScripts? _tryBuildScripts(String base, String prefix) {
    final normalizedPrefix = prefix.replaceAll('\\', '/');
    final scriptsDir = _resolveRelative(base, '${normalizedPrefix}scripts/');
    final startPath = _resolveRelative(scriptsDir, 'start-demo.ps1');
    final stopPath = _resolveRelative(scriptsDir, 'stop-demo.ps1');

    final startFile = File(startPath);
    final stopFile = File(stopPath);

    if (!startFile.existsSync() || !stopFile.existsSync()) {
      return null;
    }

    final projectRoot = normalizedPrefix.isEmpty
        ? base
        : _resolveRelative(base, normalizedPrefix);
    final statePath = _resolveRelative(scriptsDir, '.demo-state.json');

    return _ResolvedScripts(
      projectRoot: projectRoot,
      startScript: startFile,
      stopScript: stopFile,
      stateFile: File(statePath),
    );
  }

  String _resolveRelative(String basePath, String relativePath) {
    final baseUri = Directory(basePath).uri;
    return baseUri
        .resolve(relativePath.replaceAll('\\', '/'))
        .toFilePath(windows: Platform.isWindows);
  }

  Future<void> _startDemo() async {
    final scripts = _resolveScripts();
    if (scripts == null) {
      setState(() {
        _statusText = 'No se encontraron scripts';
        _detailsText = 'No se puede iniciar la demo sin scripts.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _statusText = 'Iniciando demo...';
      _detailsText = 'Espera mientras se preparan los servicios.';
    });

    final args = <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      scripts.startScript.path,
      if (_forceRestart) '-ForceRestart',
    ];

    final result = await _runPowerShell(
      args: args,
      workingDirectory: scripts.projectRoot,
    );

    final running = await scripts.stateFile.exists();

    setState(() {
      _isBusy = false;
      _isRunning = running;
      _statusText =
          result.exitCode == 0 ? 'Demo en ejecucion' : 'Fallo al iniciar';
      _detailsText = _buildDetails(result);
    });
  }

  Future<void> _stopDemo() async {
    final scripts = _resolveScripts();
    if (scripts == null) {
      setState(() {
        _statusText = 'No se encontraron scripts';
        _detailsText = 'No se puede detener la demo sin scripts.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _statusText = 'Deteniendo demo...';
      _detailsText = 'Cerrando ventanas de backend y frontend.';
    });

    final result = await _runPowerShell(
      args: <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scripts.stopScript.path,
      ],
      workingDirectory: scripts.projectRoot,
    );

    final running = await scripts.stateFile.exists();

    setState(() {
      _isBusy = false;
      _isRunning = running;
      _statusText = running ? 'Demo en ejecucion' : 'Demo detenida';
      _detailsText = _buildDetails(result);
    });
  }

  Future<_CommandResult> _runPowerShell({
    required List<String> args,
    required String workingDirectory,
  }) async {
    try {
      final process = await Process.start(
        'powershell.exe',
        args,
        workingDirectory: workingDirectory,
      );

      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode;

      return _CommandResult(
        exitCode: exitCode,
        stdoutText: (await stdoutFuture).trim(),
        stderrText: (await stderrFuture).trim(),
      );
    } catch (error) {
      return _CommandResult(
        exitCode: 1,
        stdoutText: '',
        stderrText: error.toString(),
      );
    }
  }

  String _buildDetails(_CommandResult result) {
    final combined = <String>[];
    if (result.stdoutText.isNotEmpty) {
      combined.add(result.stdoutText);
    }
    if (result.stderrText.isNotEmpty) {
      combined.add(result.stderrText);
    }

    if (combined.isEmpty) {
      return 'Comando finalizado con codigo ${result.exitCode}.';
    }

    final text = combined.join('\n');
    if (text.length <= 500) {
      return text;
    }
    return '${text.substring(0, 500)}...';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Control Demo PAE'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusText,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _detailsText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _forceRestart,
              onChanged: _isBusy
                  ? null
                  : (value) {
                      setState(() {
                        _forceRestart = value;
                      });
                    },
              title: const Text('Reiniciar sesion activa automaticamente'),
              subtitle: const Text(
                'Evita el error de sesion activa al iniciar.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_isBusy || _isRunning) ? null : _startDemo,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Iniciar demo'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (_isBusy || !_isRunning) ? null : _stopDemo,
              icon: const Icon(Icons.stop),
              label: const Text('Detener demo'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _isBusy ? null : _refreshState,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar estado'),
            ),
            if (_isBusy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResolvedScripts {
  const _ResolvedScripts({
    required this.projectRoot,
    required this.startScript,
    required this.stopScript,
    required this.stateFile,
  });

  final String projectRoot;
  final File startScript;
  final File stopScript;
  final File stateFile;
}

class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}
