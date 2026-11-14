import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/git_service.dart';
import '../services/project_service.dart';
import 'cursor_theme.dart';

/// Panel Source Control estilo Cursor.
///
/// Conexión típica en el sidebar:
/// ```dart
/// GitScmPanel(
///   projectPath: projectPath,
///   onOpenFile: (path) => openInEditor(path),
///   onGenerateCommitMessage: (diff) async => await openAi.suggestCommit(diff),
/// )
/// ```
class GitScmPanel extends StatefulWidget {
  final String? projectPath;

  /// Abre un archivo del proyecto en el editor (ruta absoluta o relativa).
  final void Function(String filePath)? onOpenFile;

  /// Callback opcional para generar mensaje con IA a partir del diff.
  /// Si es null, se usa [GitService.suggestConventionalCommitMessage].
  final Future<String> Function(String diffSummary)? onGenerateCommitMessage;

  /// Abrir pantalla de settings Git (remoto, init, …).
  final VoidCallback? onOpenSettings;

  const GitScmPanel({
    super.key,
    this.projectPath,
    this.onOpenFile,
    this.onGenerateCommitMessage,
    this.onOpenSettings,
  });

  @override
  State<GitScmPanel> createState() => _GitScmPanelState();
}

class _GitScmPanelState extends State<GitScmPanel> {
  final TextEditingController _commitController = TextEditingController();

  String? _projectPath;
  GitRepoStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _info;

  String? _selectedPath;
  bool _selectedStaged = false;
  String? _diffText;
  bool _diffLoading = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant GitScmPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectPath != widget.projectPath) {
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _commitController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final path =
        widget.projectPath ?? await ProjectService.getProjectPath();
    _projectPath = path;
    await _refresh();
  }

  Future<void> _refresh() async {
    final path = _projectPath;
    if (path == null || path.isEmpty) {
      setState(() {
        _loading = false;
        _status = null;
        _error = 'No hay proyecto seleccionado';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final status = await GitService.getStatus(path);
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
      _error = status.error;
      if (_selectedPath != null) {
        final stillThere =
            status.changes.any((c) => c.path == _selectedPath);
        if (!stillThere) {
          _selectedPath = null;
          _diffText = null;
        }
      }
    });

    if (_selectedPath != null) {
      await _loadDiff(_selectedPath!, staged: _selectedStaged);
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _info = null;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  Future<void> _loadDiff(String path, {required bool staged}) async {
    final projectPath = _projectPath;
    if (projectPath == null) return;

    setState(() {
      _selectedPath = path;
      _selectedStaged = staged;
      _diffLoading = true;
      _diffText = null;
    });

    try {
      final diff = await GitService.getFileDiff(
        projectPath,
        path,
        staged: staged,
      );
      if (!mounted) return;
      setState(() {
        _diffText = diff;
        _diffLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diffText = 'Error: $e';
        _diffLoading = false;
      });
    }
  }

  Future<void> _commit() async {
    final path = _projectPath;
    final message = _commitController.text.trim();
    if (path == null) return;
    if (message.isEmpty) {
      setState(() => _error = 'Escribe un mensaje de commit');
      return;
    }
    final staged = _status?.staged ?? [];
    if (staged.isEmpty) {
      setState(() => _error = 'No hay archivos en Staging');
      return;
    }

    await _runBusy(() async {
      final result = await GitService.commitStaged(path, message);
      _commitController.clear();
      setState(() => _info = result);
    });
  }

  Future<void> _generateCommitMessage() async {
    final path = _projectPath;
    if (path == null) return;

    setState(() {
      _busy = true;
      _info = null;
      _error = null;
    });

    try {
      final diff = await GitService.getFullDiff(path);
      String message;
      if (widget.onGenerateCommitMessage != null) {
        message = await widget.onGenerateCommitMessage!(diff);
      } else {
        message = await GitService.suggestConventionalCommitMessage(path);
      }
      if (!mounted) return;
      _commitController.text = message.trim();
      setState(() => _info = 'Mensaje de commit generado');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _badgeColor(GitChangeKind kind) {
    switch (kind) {
      case GitChangeKind.modified:
        return const Color(0xFFE2C08D);
      case GitChangeKind.added:
      case GitChangeKind.untracked:
        return const Color(0xFF89D185);
      case GitChangeKind.deleted:
        return const Color(0xFFF14C4C);
      case GitChangeKind.renamed:
      case GitChangeKind.copied:
        return const Color(0xFF75BEFF);
      default:
        return CursorTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CursorTheme.explorerBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (_error != null) _buildBanner(_error!, isError: true),
          if (_info != null) _buildBanner(_info!, isError: false),
          _buildCommitBox(),
          const Divider(height: 1, color: CursorTheme.border),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _buildBody(),
          ),
          if (_selectedPath != null) _buildDiffPane(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final branch = _status?.branch.isNotEmpty == true
        ? _status!.branch
        : '—';
    final isRepo = _status?.isRepo ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CursorTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.source, size: 14, color: CursorTheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'SOURCE CONTROL',
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (widget.onOpenSettings != null)
                _IconBtn(
                  icon: Icons.settings_outlined,
                  tooltip: 'Git settings',
                  onPressed: _busy ? null : widget.onOpenSettings,
                ),
              _IconBtn(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onPressed: _busy ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.call_split,
                size: 14,
                color: isRepo ? CursorTheme.textPrimary : CursorTheme.textDisabled,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  branch,
                  style: TextStyle(
                    color: isRepo
                        ? CursorTheme.textPrimary
                        : CursorTheme.textDisabled,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _IconBtn(
                icon: Icons.download_outlined,
                tooltip: 'Pull',
                onPressed: (!isRepo || _busy || _projectPath == null)
                    ? null
                    : () => _runBusy(() async {
                          final r = await GitService.pull(_projectPath!);
                          setState(() => _info = r);
                        }),
              ),
              _IconBtn(
                icon: Icons.upload_outlined,
                tooltip: 'Push',
                onPressed: (!isRepo || _busy || _projectPath == null)
                    ? null
                    : () => _runBusy(() async {
                          final r =
                              await GitService.push(projectPath: _projectPath!);
                          setState(() => _info = r);
                        }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(String text, {required bool isError}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: isError
          ? const Color(0x33F14C4C)
          : const Color(0x33007ACC),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? const Color(0xFFF14C4C) : CursorTheme.primary,
          fontSize: 11,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildCommitBox() {
    final stagedCount = _status?.stagedCount ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _commitController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(
              color: CursorTheme.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: 'Message (Ctrl+Enter to commit)',
              hintStyle: const TextStyle(
                color: CursorTheme.textDisabled,
                fontSize: 12,
              ),
              filled: true,
              fillColor: CursorTheme.background,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorTheme.primary),
              ),
            ),
            onSubmitted: (_) => _commit(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _generateCommitMessage,
                  icon: const Text('✨', style: TextStyle(fontSize: 12)),
                  label: const Text(
                    'Generar con IA',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CursorTheme.textPrimary,
                    side: const BorderSide(color: CursorTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_busy || stagedCount == 0) ? null : _commit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CursorTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: CursorTheme.surfaceHover,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    stagedCount == 0 ? 'Commit' : 'Commit ($stagedCount)',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final status = _status;
    if (status == null) {
      return const Center(
        child: Text(
          'Sin estado',
          style: TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
        ),
      );
    }

    if (!status.isRepo) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.source_outlined,
                  size: 36, color: CursorTheme.textDisabled),
              const SizedBox(height: 12),
              const Text(
                'No hay repositorio Git',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                status.error ?? 'Inicializa Git desde Settings',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              if (widget.onOpenSettings != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.onOpenSettings,
                  child: const Text('Abrir Git Settings'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!status.hasChanges) {
      return const Center(
        child: Text(
          'No changes',
          style: TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
        ),
      );
    }

    // Deduplicate: staged list + unstaged/untracked list
    final staged = status.staged;
    final changes = status.changes.where((c) => c.unstaged).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        _SectionHeader(
          title: 'Staged Changes',
          count: staged.length,
          trailing: staged.isEmpty
              ? null
              : TextButton(
                  onPressed: _busy
                      ? null
                      : () => _runBusy(() async {
                            for (final c in staged) {
                              await GitService.unstageFile(
                                _projectPath!,
                                c.path,
                              );
                            }
                          }),
                  child: const Text('Unstage All', style: TextStyle(fontSize: 10)),
                ),
        ),
        if (staged.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'No staged changes',
              style: TextStyle(color: CursorTheme.textDisabled, fontSize: 11),
            ),
          )
        else
          ...staged.map((c) => _buildChangeTile(c, inStagedSection: true)),
        _SectionHeader(
          title: 'Changes',
          count: changes.length,
          trailing: changes.isEmpty
              ? null
              : TextButton(
                  onPressed: _busy
                      ? null
                      : () => _runBusy(() async {
                            await GitService.stageAll(_projectPath!);
                          }),
                  child: const Text('Stage All', style: TextStyle(fontSize: 10)),
                ),
        ),
        if (changes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'No changes',
              style: TextStyle(color: CursorTheme.textDisabled, fontSize: 11),
            ),
          )
        else
          ...changes.map((c) => _buildChangeTile(c, inStagedSection: false)),
      ],
    );
  }

  Widget _buildChangeTile(GitFileChange change, {required bool inStagedSection}) {
    final selected =
        _selectedPath == change.path && _selectedStaged == inStagedSection;
    return Material(
      color: selected ? CursorTheme.explorerItemSelected : Colors.transparent,
      child: InkWell(
        onTap: () => _loadDiff(change.path, staged: inStagedSection),
        onDoubleTap: () {
          final abs = _projectPath == null
              ? change.path
              : '$_projectPath/${change.path}';
          widget.onOpenFile?.call(abs);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  change.badge,
                  style: TextStyle(
                    color: _badgeColor(change.kind),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  change.path,
                  style: const TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (inStagedSection)
                _IconBtn(
                  icon: Icons.remove_circle_outline,
                  tooltip: 'Unstage',
                  size: 16,
                  onPressed: _busy
                      ? null
                      : () => _runBusy(() async {
                            await GitService.unstageFile(
                              _projectPath!,
                              change.path,
                            );
                          }),
                )
              else ...[
                _IconBtn(
                  icon: Icons.add_circle_outline,
                  tooltip: 'Stage',
                  size: 16,
                  onPressed: _busy
                      ? null
                      : () => _runBusy(() async {
                            await GitService.stageFile(
                              _projectPath!,
                              change.path,
                            );
                          }),
                ),
                _IconBtn(
                  icon: Icons.undo,
                  tooltip: 'Discard',
                  size: 16,
                  onPressed: _busy
                      ? null
                      : () => _confirmDiscard(change.path),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        title: const Text(
          'Discard changes?',
          style: TextStyle(color: CursorTheme.textPrimary, fontSize: 16),
        ),
        content: Text(
          'Se perderán los cambios locales de:\n$path',
          style: const TextStyle(color: CursorTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _runBusy(() async {
        await GitService.discardChanges(_projectPath!, path);
        setState(() => _info = 'Cambios descartados: $path');
      });
    }
  }

  Widget _buildDiffPane() {
    return Container(
      height: 180,
      decoration: const BoxDecoration(
        color: CursorTheme.codeBackground,
        border: Border(top: BorderSide(color: CursorTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: CursorTheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedStaged ? 'Staged' : 'Working'} · $_selectedPath',
                    style: const TextStyle(
                      color: CursorTheme.textSecondary,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _IconBtn(
                  icon: Icons.copy_outlined,
                  tooltip: 'Copy diff',
                  size: 14,
                  onPressed: _diffText == null
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: _diffText!),
                          );
                          setState(() => _info = 'Diff copiado');
                        },
                ),
                _IconBtn(
                  icon: Icons.close,
                  tooltip: 'Close diff',
                  size: 14,
                  onPressed: () {
                    setState(() {
                      _selectedPath = null;
                      _diffText = null;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _diffLoading
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText.rich(
                      TextSpan(children: _colorizeDiff(_diffText ?? '')),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.35,
                        color: CursorTheme.codeText,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _colorizeDiff(String diff) {
    final spans = <TextSpan>[];
    for (final line in diff.split('\n')) {
      Color color = CursorTheme.codeText;
      if (line.startsWith('+') && !line.startsWith('+++')) {
        color = const Color(0xFF89D185);
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        color = const Color(0xFFF14C4C);
      } else if (line.startsWith('@@')) {
        color = const Color(0xFF75BEFF);
      } else if (line.startsWith('diff ') || line.startsWith('index ')) {
        color = CursorTheme.textSecondary;
      }
      spans.add(TextSpan(text: '$line\n', style: TextStyle(color: color)));
    }
    return spans;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$title${count > 0 ? ' · $count' : ''}',
              style: const TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: size),
      tooltip: tooltip,
      color: CursorTheme.textSecondary,
      disabledColor: CursorTheme.textDisabled,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onPressed,
    );
  }
}
