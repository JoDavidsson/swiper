import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/deck_provider.dart';

enum _ReviewSource { queue, sampling }

enum _ReviewMode { operations, training }

class AdminReviewScreen extends ConsumerStatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  ConsumerState<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends ConsumerState<AdminReviewScreen> {
  static const List<String> _categories = <String>[
    'sofa',
    'armchair',
    'dining_table',
    'coffee_table',
    'bed',
    'chair',
    'rug',
    'lamp',
    'storage',
    'desk',
    'decor',
    'textile',
    'unknown',
  ];

  _ReviewSource _source = _ReviewSource.queue;
  _ReviewMode _mode = _ReviewMode.operations;
  String _samplingStrategy = 'uncertain';
  String _targetCategory = 'sofa';
  bool _loading = true;
  bool _classifying = false;
  bool _training = false;
  String? _error;
  List<Map<String, dynamic>> _entries = <Map<String, dynamic>>[];
  final Set<String> _submittingIds = <String>{};
  final FocusNode _hotkeyFocusNode =
      FocusNode(debugLabel: 'review_lab_hotkeys');
  int _activeIndex = 0;
  Map<String, dynamic>? _samplingMix;
  int? _samplingScannedItems;

  @override
  void initState() {
    super.initState();
    _load();
    _requestHotkeyFocus();
  }

  @override
  void dispose() {
    _hotkeyFocusNode.dispose();
    super.dispose();
  }

  void _requestHotkeyFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hotkeyFocusNode.requestFocus();
    });
  }

  int _clampActiveIndex(int value, int length) {
    if (length <= 0) return 0;
    if (value < 0) return 0;
    if (value >= length) return length - 1;
    return value;
  }

  Map<String, dynamic>? _activeEntry() {
    if (_entries.isEmpty) return null;
    final idx = _clampActiveIndex(_activeIndex, _entries.length);
    return _entries[idx];
  }

  void _setSource(_ReviewSource source) {
    if (source == _source) return;
    setState(() {
      _source = source;
      _mode = source == _ReviewSource.queue
          ? _ReviewMode.operations
          : _ReviewMode.training;
      _activeIndex = 0;
    });
    _load();
  }

  void _setMode(_ReviewMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
    });
  }

  void _setSamplingStrategy(String strategy) {
    if (strategy == _samplingStrategy) return;
    setState(() {
      _samplingStrategy = strategy;
      _activeIndex = 0;
    });
    _load();
  }

  void _setTargetCategory(String category) {
    if (category == _targetCategory) return;
    setState(() {
      _targetCategory = category;
      _activeIndex = 0;
    });
    if (_source == _ReviewSource.sampling) {
      _load();
    }
  }

  void _moveActive(int delta) {
    if (_entries.isEmpty) return;
    setState(() {
      _activeIndex = _clampActiveIndex(_activeIndex + delta, _entries.length);
    });
  }

  Future<void> _triggerAction(String action) async {
    final entry = _activeEntry();
    if (entry == null) return;
    if (_submittingIds.contains(_itemId(entry))) return;

    if (action == 'in_category') {
      await _submitBinaryLabel(entry, true);
      return;
    }
    if (action == 'not_category') {
      await _submitBinaryLabel(entry, false);
      return;
    }
    if (action == 'reclassify') {
      if (_mode == _ReviewMode.training) return;
      await _openReclassifyDialog(entry);
      return;
    }
    if (action == 'skip') {
      _skipEntry(entry);
      return;
    }
    await _submitAction(entry, action);
  }

  void _skipEntry(Map<String, dynamic> entry) {
    final id = _itemId(entry);
    if (id.isEmpty) return;
    setState(() {
      _entries = _entries.where((e) => _itemId(e) != id).toList();
      _activeIndex = _clampActiveIndex(_activeIndex, _entries.length);
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_loading || _classifying || _training) return KeyEventResult.ignored;

    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed || hw.isMetaPressed || hw.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyJ) {
      _moveActive(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyK) {
      _moveActive(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      _triggerAction(_mode == _ReviewMode.training ? 'in_category' : 'accept');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.keyX) {
      _triggerAction(_mode == _ReviewMode.training ? 'not_category' : 'reject');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      if (_mode == _ReviewMode.operations) {
        _triggerAction('reclassify');
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      _triggerAction('skip');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      _trainCategorizer();
      return KeyEventResult.handled;
    }
    if (_source == _ReviewSource.sampling && key == LogicalKeyboardKey.digit1) {
      _setSamplingStrategy('uncertain');
      return KeyEventResult.handled;
    }
    if (_source == _ReviewSource.sampling && key == LogicalKeyboardKey.digit2) {
      _setSamplingStrategy('diverse');
      return KeyEventResult.handled;
    }
    if (_source == _ReviewSource.sampling && key == LogicalKeyboardKey.digit3) {
      _setSamplingStrategy('random');
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      final data = _source == _ReviewSource.queue
          ? await client.adminGetReviewQueue(status: 'pending', limit: 80)
          : await client.adminGetSamplingCandidates(
              strategy: _samplingStrategy,
              limit: 80,
              targetCategory: _targetCategory,
            );
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      if (!mounted) return;
      setState(() {
        _entries = items;
        _activeIndex = _clampActiveIndex(_activeIndex, _entries.length);
        _samplingMix = data['samplingMix'] is Map
            ? Map<String, dynamic>.from(data['samplingMix'] as Map)
            : null;
        _samplingScannedItems = data['scannedItems'] is num
            ? (data['scannedItems'] as num).toInt()
            : null;
        _loading = false;
      });
      _requestHotkeyFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      _requestHotkeyFocus();
    }
  }

  Future<void> _classifySeed() async {
    setState(() {
      _classifying = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final result = await client.adminClassify(limit: 300);
      if (!mounted) return;
      final processed = result['processed'] ?? 0;
      final uncertain = result['uncertain'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Classified $processed items, queued $uncertain for review.'),
        ),
      );
      if (_source == _ReviewSource.queue) {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Classification failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _classifying = false;
        });
        _requestHotkeyFocus();
      }
    }
  }

  Future<void> _trainCategorizer() async {
    setState(() {
      _training = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final result =
          await client.adminTrainCategorizer(category: _targetCategory);
      if (!mounted) return;

      final labelsUsed = result['labelsUsed'] ?? 0;
      final recommendedMin = result['recommendedMinLabels'] ?? 150;
      final recommendedGood = result['recommendedGoodLabels'] ?? 400;
      final runtimeStatus = result['runtimeStatus']?.toString() ?? 'unknown';
      final evaluation = result['evaluation'] is Map
          ? Map<String, dynamic>.from(result['evaluation'] as Map)
          : <String, dynamic>{};
      final gate = evaluation['gate'] is Map
          ? Map<String, dynamic>.from(evaluation['gate'] as Map)
          : <String, dynamic>{};
      final baseline = evaluation['baseline'] is Map
          ? Map<String, dynamic>.from(evaluation['baseline'] as Map)
          : <String, dynamic>{};
      final adjusted = evaluation['adjusted'] is Map
          ? Map<String, dynamic>.from(evaluation['adjusted'] as Map)
          : <String, dynamic>{};
      final precisionDelta =
          (evaluation['precisionDelta'] as num?)?.toDouble() ?? 0.0;
      final recallDelta =
          (evaluation['recallDelta'] as num?)?.toDouble() ?? 0.0;
      final findings = (result['topFindings'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Training completed'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Labels used: $labelsUsed'),
                  const SizedBox(height: 6),
                  Text('Target category: $_targetCategory'),
                  const SizedBox(height: 6),
                  Text('Recommended minimum: $recommendedMin'),
                  Text('Recommended good quality: $recommendedGood'),
                  const SizedBox(height: 6),
                  Text('Runtime status: $runtimeStatus'),
                  if (evaluation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Holdout gate: ${gate['passed'] == true ? 'PASS' : 'SHADOW'} (${gate['reason'] ?? 'n/a'})',
                    ),
                    Text(
                      'Precision ${_fmtPct(baseline['precision'])} -> ${_fmtPct(adjusted['precision'])} (${(precisionDelta * 100).toStringAsFixed(1)} pp)',
                    ),
                    Text(
                      'Recall ${_fmtPct(baseline['recall'])} -> ${_fmtPct(adjusted['recall'])} (${(recallDelta * 100).toStringAsFixed(1)} pp)',
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Top source/category issues:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (findings.isEmpty)
                    const Text(
                        'No strong cross-source failure patterns found yet.')
                  else
                    ...findings.take(6).map((finding) {
                      final source =
                          finding['sourceId']?.toString() ?? 'unknown';
                      final category =
                          finding['predictedCategory']?.toString() ?? 'unknown';
                      final rejectRate =
                          ((finding['rejectRate'] as num?)?.toDouble() ?? 0.0) *
                              100;
                      final sampleSize = finding['sampleSize'] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '$source / $category: ${rejectRate.toStringAsFixed(0)}% rejects ($sampleSize labels)',
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Training failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _training = false;
        });
        _requestHotkeyFocus();
      }
    }
  }

  Future<void> _submitBinaryLabel(
    Map<String, dynamic> entry,
    bool isInCategory,
  ) async {
    final hasImage = _firstImageUrl(entry) != null;
    final reason = isInCategory
        ? 'in_target_category'
        : (hasImage ? 'not_target_category' : 'missing_image');

    await _submitAction(
      entry,
      isInCategory ? 'accept' : 'reject',
      reason: reason,
      trainingOnly: true,
      labelCategory: _targetCategory,
      labelDecision: isInCategory ? 'in_category' : 'not_category',
    );
  }

  String _itemId(Map<String, dynamic> entry) {
    final id = entry['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    final itemId = entry['itemId']?.toString();
    if (itemId != null && itemId.isNotEmpty) return itemId;
    return '';
  }

  Map<String, dynamic> _itemContext(Map<String, dynamic> entry) {
    final nested = entry['item'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return entry;
  }

  Map<String, dynamic> _classification(Map<String, dynamic> entry) {
    final direct = entry['classification'];
    if (direct is Map) {
      return Map<String, dynamic>.from(direct);
    }
    final fromItem = _itemContext(entry)['classification'];
    if (fromItem is Map) {
      return Map<String, dynamic>.from(fromItem);
    }
    return <String, dynamic>{};
  }

  String? _firstImageUrl(Map<String, dynamic> entry) {
    final item = _itemContext(entry);
    final fromImages = _extractImageUrl(item['images']);
    if (fromImages != null) return fromImages;
    final fromImageUrl = _extractImageUrl(item['imageUrl']);
    if (fromImageUrl != null) return fromImageUrl;
    final fromImage = _extractImageUrl(item['image']);
    if (fromImage != null) return fromImage;
    return null;
  }

  String? _extractImageUrl(dynamic value, [int depth = 0]) {
    if (value == null || depth > 2) return null;

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return trimmed;
    }

    if (value is List) {
      for (final entry in value) {
        final found = _extractImageUrl(entry, depth + 1);
        if (found != null) return found;
      }
      return null;
    }

    if (value is Map) {
      final data = Map<String, dynamic>.from(value);
      const keyCandidates = <String>[
        'url',
        'src',
        'imageUrl',
        'image_url',
        'original',
        'originalUrl',
        'large',
        'largeUrl',
        'thumbnail',
        'thumb',
        'small',
        'secure_url',
        'href',
      ];
      for (final key in keyCandidates) {
        final found = _extractImageUrl(data[key], depth + 1);
        if (found != null) return found;
      }
      return null;
    }

    return null;
  }

  String _fmtPct(dynamic value) {
    final number = value is num ? value.toDouble() : 0.0;
    return '${(number * 100).toStringAsFixed(1)}%';
  }

  Future<void> _submitAction(
    Map<String, dynamic> entry,
    String action, {
    String? correctCategory,
    String? reason,
    bool trainingOnly = false,
    String? labelCategory,
    String? labelDecision,
  }) async {
    final id = _itemId(entry);
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing item id.')),
      );
      return;
    }

    setState(() {
      _submittingIds.add(id);
    });

    try {
      final client = ref.read(apiClientProvider);
      await client.adminReviewAction(
        itemId: id,
        action: action,
        correctCategory: correctCategory,
        reason: reason,
        trainingOnly: trainingOnly,
        labelCategory: labelCategory,
        labelDecision: labelDecision,
      );
      if (!mounted) return;
      setState(() {
        _entries = _entries.where((e) => _itemId(e) != id).toList();
        _activeIndex = _clampActiveIndex(_activeIndex, _entries.length);
      });
      final savedText = labelDecision == null
          ? 'Saved $action for $id.'
          : (labelDecision == 'in_category'
              ? 'Saved $_targetCategory for $id.'
              : 'Saved not $_targetCategory for $id.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(savedText)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save action: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingIds.remove(id);
        });
        _requestHotkeyFocus();
      }
    }
  }

  Future<void> _openReclassifyDialog(Map<String, dynamic> entry) async {
    final cls = _classification(entry);
    String category = cls['primaryCategory']?.toString() ??
        cls['predictedCategory']?.toString() ??
        'sofa';
    if (!_categories.contains(category)) category = 'sofa';
    final reasonController = TextEditingController();

    final chosen = await showDialog<(String, String?)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Reclassify item'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    items: _categories
                        .map((c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setLocal(() {
                          category = value;
                        });
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Correct category',
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingUnit),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context)
                        .pop((category, reasonController.text.trim()));
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
    if (chosen == null) {
      _requestHotkeyFocus();
      return;
    }
    await _submitAction(
      entry,
      'reclassify',
      correctCategory: chosen.$1,
      reason: chosen.$2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Review Lab'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        focusNode: _hotkeyFocusNode,
        onKeyEvent: _onKeyEvent,
        child: Column(
          children: [
            Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<_ReviewSource>(
                    segments: const [
                      ButtonSegment<_ReviewSource>(
                        value: _ReviewSource.queue,
                        label: Text('Review queue'),
                        icon: Icon(Icons.assignment_outlined),
                      ),
                      ButtonSegment<_ReviewSource>(
                        value: _ReviewSource.sampling,
                        label: Text('Sampling'),
                        icon: Icon(Icons.science_outlined),
                      ),
                    ],
                    selected: <_ReviewSource>{_source},
                    onSelectionChanged: (selection) =>
                        _setSource(selection.first),
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 0.75),
                  SegmentedButton<_ReviewMode>(
                    segments: const [
                      ButtonSegment<_ReviewMode>(
                        value: _ReviewMode.operations,
                        label: Text('Operations'),
                        icon: Icon(Icons.rule_folder_outlined),
                      ),
                      ButtonSegment<_ReviewMode>(
                        value: _ReviewMode.training,
                        label: Text('Training'),
                        icon: Icon(Icons.school_outlined),
                      ),
                    ],
                    selected: <_ReviewMode>{_mode},
                    onSelectionChanged: (selection) =>
                        _setMode(selection.first),
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 0.75),
                  DropdownButtonFormField<String>(
                    initialValue: _targetCategory,
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      _setTargetCategory(value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Target category',
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 0.75),
                  Row(
                    children: [
                      if (_source == _ReviewSource.sampling)
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _samplingStrategy,
                            items: const [
                              DropdownMenuItem(
                                  value: 'uncertain', child: Text('Uncertain')),
                              DropdownMenuItem(
                                  value: 'diverse', child: Text('Diverse')),
                              DropdownMenuItem(
                                  value: 'random', child: Text('Random')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              _setSamplingStrategy(value);
                            },
                            decoration: const InputDecoration(
                              labelText: 'Sampling strategy',
                            ),
                          ),
                        ),
                      if (_source == _ReviewSource.sampling)
                        const SizedBox(width: AppTheme.spacingUnit),
                      ElevatedButton.icon(
                        onPressed:
                            (_classifying || _training) ? null : _classifySeed,
                        icon: _classifying
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_fix_high),
                        label: Text(
                            _classifying ? 'Classifying...' : 'Seed queue'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: (_training || _classifying)
                            ? null
                            : _trainCategorizer,
                        icon: _training
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.model_training),
                        label: Text(_training ? 'Training...' : 'Train'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 0.75),
                  Text(
                    _mode == _ReviewMode.training
                        ? 'Question: Is this item in "$_targetCategory"?'
                        : 'Question: Operational decision for queue item (accept/reject/reclassify).',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textSecondary),
                  ),
                  if (_source == _ReviewSource.sampling &&
                      _samplingMix != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sampling mix: primary ${_samplingMix?['selectedPrimary'] ?? 0}, near-miss ${_samplingMix?['selectedNearMiss'] ?? 0}, backfill ${_samplingMix?['selectedBackfill'] ?? 0}${_samplingScannedItems != null ? ' (scanned $_samplingScannedItems items)' : ''}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textCaption),
                    ),
                  ],
                  const SizedBox(height: AppTheme.spacingUnit * 0.75),
                  Text(
                    '${_entries.length} items ready for labeling',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _source == _ReviewSource.sampling
                        ? (_mode == _ReviewMode.training
                            ? 'Hotkeys: A = $_targetCategory, D = not $_targetCategory, S skip, J/K or ↑/↓ move, T train, 1/2/3 strategy'
                            : 'Hotkeys: A accept, D reject, R reclassify, S skip, J/K or ↑/↓ move, T train, 1/2/3 strategy')
                        : (_mode == _ReviewMode.training
                            ? 'Hotkeys: A = $_targetCategory, D = not $_targetCategory, S skip, J/K or ↑/↓ move, T train'
                            : 'Hotkeys: A accept, D reject, R reclassify, S skip, J/K or ↑/↓ move, T train'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textCaption),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 44),
              const SizedBox(height: AppTheme.spacingUnit),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: AppTheme.spacingUnit),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingUnit * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined,
                  color: AppTheme.textCaption, size: 46),
              const SizedBox(height: AppTheme.spacingUnit),
              Text(
                _source == _ReviewSource.queue
                    ? 'No pending review items. Click Seed queue to classify and enqueue uncertain items.'
                    : 'No sampled items returned. Refresh or change sampling strategy.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _ReviewCard(
            entry: entry,
            imageUrl: _firstImageUrl(entry),
            classification: _classification(entry),
            itemData: _itemContext(entry),
            busy: _submittingIds.contains(_itemId(entry)),
            isActive: index == _activeIndex,
            questionText: _mode == _ReviewMode.training
                ? 'Is this $_targetCategory?'
                : 'Operational review',
            samplingReason: entry['samplingReason']?.toString(),
            acceptLabel:
                _mode == _ReviewMode.training ? _targetCategory : 'Accept',
            rejectLabel: _mode == _ReviewMode.training
                ? 'Not $_targetCategory'
                : 'Reject',
            onAccept: () => _mode == _ReviewMode.training
                ? _submitBinaryLabel(entry, true)
                : _submitAction(entry, 'accept'),
            onReject: () => _mode == _ReviewMode.training
                ? _submitBinaryLabel(entry, false)
                : _submitAction(entry, 'reject'),
            onReclassify: () => _openReclassifyDialog(entry),
            onSkip: () => _skipEntry(entry),
            showReclassify: _mode == _ReviewMode.operations,
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.entry,
    required this.itemData,
    required this.classification,
    required this.imageUrl,
    required this.busy,
    required this.isActive,
    required this.questionText,
    required this.samplingReason,
    required this.acceptLabel,
    required this.rejectLabel,
    required this.onAccept,
    required this.onReject,
    required this.onReclassify,
    required this.onSkip,
    required this.showReclassify,
  });

  final Map<String, dynamic> entry;
  final Map<String, dynamic> itemData;
  final Map<String, dynamic> classification;
  final String? imageUrl;
  final bool busy;
  final bool isActive;
  final String questionText;
  final String? samplingReason;
  final String acceptLabel;
  final String rejectLabel;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onReclassify;
  final VoidCallback onSkip;
  final bool showReclassify;

  @override
  Widget build(BuildContext context) {
    final title = itemData['title']?.toString() ?? 'Untitled';
    final brand = itemData['brand']?.toString() ?? '';
    final source = itemData['sourceId']?.toString() ?? '';
    final predicted = classification['primaryCategory']?.toString() ??
        classification['predictedCategory']?.toString() ??
        'unknown';
    final confidence = _asDouble(
      classification['top1Confidence'] ?? classification['categoryConfidence'],
    );
    final probabilityText =
        _topProbabilities(classification['categoryProbabilities']);

    final priceRaw = itemData['priceAmount'];
    final currency = itemData['priceCurrency']?.toString() ?? 'SEK';
    final price =
        priceRaw is num ? '${priceRaw.toStringAsFixed(0)} $currency' : '-';

    final proxiedImage = imageUrl != null
        ? ApiClient.proxyImageUrl(imageUrl!, width: ImageWidth.thumbnail)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(
          color: isActive ? AppTheme.primaryAction : Colors.transparent,
          width: isActive ? 2 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: proxiedImage != null
                        ? Image.network(
                            proxiedImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) {
                              if (imageUrl != null &&
                                  proxiedImage != imageUrl) {
                                return Image.network(
                                  imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _placeholder(),
                                );
                              }
                              return _placeholder();
                            },
                          )
                        : _placeholder(),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingUnit),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [brand, source].where((s) => s.isNotEmpty).join(' • '),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        price,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.priceHighlight,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit * 0.75),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('Predicted: $predicted'),
                _chip('Confidence: ${(confidence * 100).toStringAsFixed(0)}%'),
                _chip(questionText),
                if (samplingReason != null && samplingReason!.isNotEmpty)
                  _chip('Sample: $samplingReason'),
                if (probabilityText.isNotEmpty) _chip(probabilityText),
              ],
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 160,
                  child: FilledButton(
                      onPressed: busy ? null : onAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(acceptLabel)),
                ),
                SizedBox(
                  width: 160,
                  child: FilledButton.tonal(
                    onPressed: busy ? null : onReject,
                    style: FilledButton.styleFrom(
                      foregroundColor: AppTheme.error,
                    ),
                    child: Text(rejectLabel),
                  ),
                ),
                if (showReclassify)
                  SizedBox(
                    width: 160,
                    child: OutlinedButton(
                      onPressed: busy ? null : onReclassify,
                      child: const Text('Reclassify'),
                    ),
                  ),
                SizedBox(
                  width: 100,
                  child: OutlinedButton(
                    onPressed: busy ? null : onSkip,
                    child: const Text('Skip'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppTheme.surfaceVariant,
      child: const Icon(Icons.image_not_supported, color: AppTheme.textCaption),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return 0.0;
  }

  String _topProbabilities(dynamic probabilitiesRaw) {
    if (probabilitiesRaw is! Map) return '';
    final entries = probabilitiesRaw.entries
        .map((e) => MapEntry(e.key.toString(), _asDouble(e.value)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(3).toList();
    if (top.isEmpty) return '';
    return top
        .map((e) => '${e.key}:${(e.value * 100).toStringAsFixed(0)}%')
        .join('  ');
  }
}
