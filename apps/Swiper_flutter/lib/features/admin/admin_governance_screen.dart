import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/deck_provider.dart';

/// Pacing strategy options
enum PacingStrategy { even, frontload, backload }

extension PacingStrategyExtension on PacingStrategy {
  String get label {
    switch (this) {
      case PacingStrategy.even:
        return 'Even';
      case PacingStrategy.frontload:
        return 'Frontload';
      case PacingStrategy.backload:
        return 'Backload';
    }
  }

  static PacingStrategy fromString(String? value) {
    switch (value) {
      case 'frontload':
        return PacingStrategy.frontload;
      case 'backload':
        return PacingStrategy.backload;
      default:
        return PacingStrategy.even;
    }
  }
}

/// Global governance config state
class GovernanceConfig {
  final int frequencyCap;
  final int relevanceThreshold;
  final PacingStrategy pacingStrategy;
  final bool brandSafetyEnabled;
  final String featuredLabelText;

  const GovernanceConfig({
    this.frequencyCap = 10,
    this.relevanceThreshold = 50,
    this.pacingStrategy = PacingStrategy.even,
    this.brandSafetyEnabled = true,
    this.featuredLabelText = 'Featured',
  });

  GovernanceConfig copyWith({
    int? frequencyCap,
    int? relevanceThreshold,
    PacingStrategy? pacingStrategy,
    bool? brandSafetyEnabled,
    String? featuredLabelText,
  }) {
    return GovernanceConfig(
      frequencyCap: frequencyCap ?? this.frequencyCap,
      relevanceThreshold: relevanceThreshold ?? this.relevanceThreshold,
      pacingStrategy: pacingStrategy ?? this.pacingStrategy,
      brandSafetyEnabled: brandSafetyEnabled ?? this.brandSafetyEnabled,
      featuredLabelText: featuredLabelText ?? this.featuredLabelText,
    );
  }

  Map<String, dynamic> toJson() => {
        'frequencyCap': frequencyCap,
        'relevanceThreshold': relevanceThreshold,
        'pacingStrategy': pacingStrategy.name,
        'brandSafetyEnabled': brandSafetyEnabled,
        'featuredLabelText': featuredLabelText,
      };

  factory GovernanceConfig.fromJson(Map<String, dynamic> json) {
    return GovernanceConfig(
      frequencyCap: (json['frequencyCap'] as num?)?.toInt() ?? 10,
      relevanceThreshold: (json['relevanceThreshold'] as num?)?.toInt() ?? 50,
      pacingStrategy:
          PacingStrategyExtension.fromString(json['pacingStrategy'] as String?),
      brandSafetyEnabled: json['brandSafetyEnabled'] as bool? ?? true,
      featuredLabelText: json['featuredLabelText'] as String? ?? 'Featured',
    );
  }
}

class AdminGovernanceScreen extends ConsumerStatefulWidget {
  const AdminGovernanceScreen({super.key});

  @override
  ConsumerState<AdminGovernanceScreen> createState() =>
      _AdminGovernanceScreenState();
}

class _AdminGovernanceScreenState extends ConsumerState<AdminGovernanceScreen> {
  GovernanceConfig _globalConfig = const GovernanceConfig();
  List<Map<String, dynamic>> _retailers = [];
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final results = await Future.wait([
        client.adminGetGovernance(),
        client.adminGetRetailers(),
      ]);
      setState(() {
        _globalConfig =
            GovernanceConfig.fromJson(results[0] as Map<String, dynamic>);
        _retailers = (results[1] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _patchGlobalGovernance(GovernanceConfig newConfig) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).adminPatchGovernance(newConfig.toJson());
      setState(() {
        _globalConfig = newConfig;
        _saving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Governance config updated')),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating config: $e')),
        );
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to defaults?'),
        content: const Text(
          'This will reset the global governance config to default values. '
          'Retailer overrides will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(apiClientProvider).adminResetGovernance();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Governance reset to defaults')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error resetting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Governance'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: AppTheme.negativeDislike),
            const SizedBox(height: AppTheme.spacingUnit),
            Text('Error loading governance data',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingUnit / 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: AppTheme.spacingUnit),
            ElevatedButton(
                onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.spacingUnit),
        children: [
          // Global Governance Section
          _SectionHeader(title: 'Global Governance'),
          Card(
            margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Frequency Cap
                  _SliderControl(
                    label: 'Frequency Cap',
                    value: _globalConfig.frequencyCap.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    valueLabel: '${_globalConfig.frequencyCap} items/day',
                    onChanged: (value) {
                      final newConfig = _globalConfig.copyWith(
                        frequencyCap: value.round(),
                      );
                      _patchGlobalGovernance(newConfig);
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 1.5),

                  // Relevance Threshold
                  _SliderControl(
                    label: 'Relevance Threshold',
                    value: _globalConfig.relevanceThreshold.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    valueLabel: '${_globalConfig.relevanceThreshold}%',
                    onChanged: (value) {
                      final newConfig = _globalConfig.copyWith(
                        relevanceThreshold: value.round(),
                      );
                      _patchGlobalGovernance(newConfig);
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 1.5),

                  // Pacing Strategy
                  Text(
                    'Pacing Strategy',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppTheme.spacingUnit / 2),
                  SegmentedButton<PacingStrategy>(
                    segments: PacingStrategy.values
                        .map((s) => ButtonSegment<PacingStrategy>(
                              value: s,
                              label: Text(s.label),
                            ))
                        .toList(),
                    selected: {_globalConfig.pacingStrategy},
                    onSelectionChanged: (selection) {
                      final newConfig = _globalConfig.copyWith(
                        pacingStrategy: selection.first,
                      );
                      _patchGlobalGovernance(newConfig);
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 1.5),

                  // Brand Safety Toggle
                  _ToggleControl(
                    label: 'Brand Safety Enabled',
                    value: _globalConfig.brandSafetyEnabled,
                    onChanged: (value) {
                      final newConfig = _globalConfig.copyWith(
                        brandSafetyEnabled: value,
                      );
                      _patchGlobalGovernance(newConfig);
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingUnit * 1.5),

                  // Featured Label Text
                  _TextFieldControl(
                    label: 'Featured Label Text',
                    value: _globalConfig.featuredLabelText,
                    onChanged: (value) {
                      final newConfig = _globalConfig.copyWith(
                        featuredLabelText: value,
                      );
                      _patchGlobalGovernance(newConfig);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Reset Button
          Center(
            child: OutlinedButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('Reset to Defaults'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.warning,
                side: const BorderSide(color: AppTheme.warning),
              ),
            ),
          ),

          const SizedBox(height: AppTheme.spacingUnit * 2),

          // Per-Retailer Overrides Section
          _SectionHeader(title: 'Per-Retailer Overrides'),
          if (_retailers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.spacingUnit),
                child: Text('No retailers found'),
              ),
            )
          else
            ..._retailers.map((retailer) => _RetailerCard(
                  retailer: retailer,
                  onTap: () => _showRetailerGovernanceSheet(context, retailer),
                )),

          const SizedBox(height: AppTheme.spacingUnit * 4),
        ],
      ),
    );
  }

  void _showRetailerGovernanceSheet(
      BuildContext context, Map<String, dynamic> retailer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _RetailerGovernanceSheet(
        retailer: retailer,
        onSaved: _loadData,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AppTheme.spacingUnit,
        top: AppTheme.spacingUnit / 2,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SliderControl extends StatelessWidget {
  const _SliderControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            Text(
              valueLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.primaryAction,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ToggleControl extends StatelessWidget {
  const _ToggleControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primaryAction,
        ),
      ],
    );
  }
}

class _TextFieldControl extends StatefulWidget {
  const _TextFieldControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextFieldControl> createState() => _TextFieldControlState();
}

class _TextFieldControlState extends State<_TextFieldControl> {
  late TextEditingController _controller;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _TextFieldControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isDirty) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppTheme.spacingUnit / 2),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: 'Enter label text',
          ),
          onChanged: (value) {
            setState(() => _isDirty = true);
          },
          onSubmitted: (value) {
            widget.onChanged(value);
            setState(() => _isDirty = false);
          },
        ),
        if (_isDirty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                widget.onChanged(_controller.text);
                setState(() => _isDirty = false);
              },
              child: const Text('Apply'),
            ),
          ),
      ],
    );
  }
}

class _RetailerCard extends StatelessWidget {
  const _RetailerCard({
    required this.retailer,
    required this.onTap,
  });

  final Map<String, dynamic> retailer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = retailer['name'] as String? ?? 'Unknown Retailer';
    final hasOverride = retailer['hasGovernanceOverride'] as bool? ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingUnit),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: hasOverride
                ? AppTheme.warning.withValues(alpha: 0.15)
                : AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            hasOverride ? Icons.tune : Icons.business,
            color: hasOverride ? AppTheme.warning : AppTheme.textCaption,
          ),
        ),
        title: Text(name),
        subtitle: Text(
          hasOverride ? 'Has governance override' : 'Using global settings',
          style: TextStyle(
            color: hasOverride ? AppTheme.warning : AppTheme.textCaption,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _RetailerGovernanceSheet extends ConsumerStatefulWidget {
  const _RetailerGovernanceSheet({
    required this.retailer,
    required this.onSaved,
  });

  final Map<String, dynamic> retailer;
  final VoidCallback onSaved;

  @override
  ConsumerState<_RetailerGovernanceSheet> createState() =>
      _RetailerGovernanceSheetState();
}

class _RetailerGovernanceSheetState
    extends ConsumerState<_RetailerGovernanceSheet> {
  GovernanceConfig _config = const GovernanceConfig();
  bool _loading = true;
  bool _saving = false;
  bool _hasOverride = false;

  @override
  void initState() {
    super.initState();
    _loadRetailerGovernance();
  }

  Future<void> _loadRetailerGovernance() async {
    final retailerId = widget.retailer['id'] as String? ?? '';
    if (retailerId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
      final client = ref.read(apiClientProvider);
      final data = await client.adminGetRetailerGovernance(retailerId);
      setState(() {
        _config = GovernanceConfig.fromJson(data);
        _hasOverride = data['hasOverride'] as bool? ?? false;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading retailer governance: $e')),
        );
      }
    }
  }

  Future<void> _saveRetailerGovernance() async {
    final retailerId = widget.retailer['id'] as String? ?? '';
    if (retailerId.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .adminPatchRetailerGovernance(retailerId, _config.toJson());
      widget.onSaved();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retailer governance updated')),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final retailerName = widget.retailer['name'] as String? ?? 'Retailer';

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.outlineSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTheme.spacingUnit),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      retailerName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_saving)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      FilledButton(
                        onPressed: _saveRetailerGovernance,
                        child: const Text('Save'),
                      ),
                  ],
                ),
              ),
              const Divider(),
              // Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scrollController,
                        padding:
                            const EdgeInsets.all(AppTheme.spacingUnit),
                        children: [
                          // Override indicator
                          if (_hasOverride)
                            Container(
                              padding: const EdgeInsets.all(
                                  AppTheme.spacingUnit),
                              margin: const EdgeInsets.only(
                                  bottom: AppTheme.spacingUnit),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusCard),
                                border: Border.all(
                                    color: AppTheme.warning
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      color: AppTheme.warning),
                                  const SizedBox(width: AppTheme.spacingUnit),
                                  Expanded(
                                    child: Text(
                                      'This retailer has custom governance settings that override global config.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Text(
                            'Override Governance Settings',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppTheme.spacingUnit),
                          // Frequency Cap
                          _SliderControl(
                            label: 'Frequency Cap',
                            value: _config.frequencyCap.toDouble(),
                            min: 1,
                            max: 50,
                            divisions: 49,
                            valueLabel: '${_config.frequencyCap} items/day',
                            onChanged: (value) {
                              setState(() {
                                _config = _config.copyWith(
                                  frequencyCap: value.round(),
                                );
                              });
                            },
                          ),
                          const SizedBox(height: AppTheme.spacingUnit * 1.5),

                          // Relevance Threshold
                          _SliderControl(
                            label: 'Relevance Threshold',
                            value: _config.relevanceThreshold.toDouble(),
                            min: 0,
                            max: 100,
                            divisions: 100,
                            valueLabel: '${_config.relevanceThreshold}%',
                            onChanged: (value) {
                              setState(() {
                                _config = _config.copyWith(
                                  relevanceThreshold: value.round(),
                                );
                              });
                            },
                          ),
                          const SizedBox(height: AppTheme.spacingUnit * 1.5),

                          // Pacing Strategy
                          Text(
                            'Pacing Strategy',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: AppTheme.spacingUnit / 2),
                          SegmentedButton<PacingStrategy>(
                            segments: PacingStrategy.values
                                .map((s) => ButtonSegment<PacingStrategy>(
                                      value: s,
                                      label: Text(s.label),
                                    ))
                                .toList(),
                            selected: {_config.pacingStrategy},
                            onSelectionChanged: (selection) {
                              setState(() {
                                _config = _config.copyWith(
                                  pacingStrategy: selection.first,
                                );
                              });
                            },
                          ),
                          const SizedBox(height: AppTheme.spacingUnit * 1.5),

                          // Brand Safety Toggle
                          _ToggleControl(
                            label: 'Brand Safety Enabled',
                            value: _config.brandSafetyEnabled,
                            onChanged: (value) {
                              setState(() {
                                _config = _config.copyWith(
                                  brandSafetyEnabled: value,
                                );
                              });
                            },
                          ),
                          const SizedBox(height: AppTheme.spacingUnit * 1.5),

                          // Featured Label Text
                          _TextFieldControl(
                            label: 'Featured Label Text',
                            value: _config.featuredLabelText,
                            onChanged: (value) {
                              setState(() {
                                _config = _config.copyWith(
                                  featuredLabelText: value,
                                );
                              });
                            },
                          ),
                          const SizedBox(height: AppTheme.spacingUnit * 2),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
