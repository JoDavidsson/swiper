import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/auth_provider.dart';
import '../../data/deck_provider.dart';
import '../../data/event_tracker.dart';

/// Decision Room screen - view and participate in a shared decision room.
/// Viewing is public; participation (vote/comment) requires authentication.
class DecisionRoomScreen extends ConsumerStatefulWidget {
  const DecisionRoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<DecisionRoomScreen> createState() => _DecisionRoomScreenState();
}

class _DecisionRoomScreenState extends ConsumerState<DecisionRoomScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _roomData;
  List<Map<String, dynamic>> _comments = [];

  @override
  void initState() {
    super.initState();
    _loadRoom();
  }

  Future<void> _loadRoom() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = ref.read(apiClientProvider);
      final roomData = await client.getDecisionRoom(widget.roomId);
      
      // Also load comments
      final commentsData = await client.getDecisionRoomComments(widget.roomId);
      final comments = (commentsData['comments'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (mounted) {
        setState(() {
          _roomData = roomData;
          _comments = comments;
          _loading = false;
        });
        
        // Track room view
        final tracker = ref.read(eventTrackerProvider);
        final authState = ref.read(authProvider);
        tracker.track('decisionroom_view', {
          'room': {
            'roomId': widget.roomId,
            'itemCount': (roomData['items'] as List?)?.length ?? 0,
            'participantCount': roomData['participantCount'] ?? 1,
          },
          'user': authState.isAuthenticated ? {'userId': authState.user?.uid} : null,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load decision room';
          _loading = false;
        });
      }
    }
  }

  Future<void> _vote(String itemId, String vote) async {
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated) {
      _promptLogin();
      return;
    }

    final token = await ref.read(authProvider.notifier).getIdToken();
    if (token == null) return;

    try {
      final client = ref.read(apiClientProvider);
      await client.voteInDecisionRoom(
        token: token,
        roomId: widget.roomId,
        itemId: itemId,
        vote: vote,
      );
      
      // Track vote event
      final tracker = ref.read(eventTrackerProvider);
      tracker.track('decisionroom_vote', {
        'room': {'roomId': widget.roomId},
        'item': {'itemId': itemId},
        'vote': {'direction': vote},
      });
      
      // Reload room to get updated vote counts
      await _loadRoom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to vote: $e')),
        );
      }
    }
  }

  Future<void> _addComment(String text) async {
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated) {
      _promptLogin();
      return;
    }

    final token = await ref.read(authProvider.notifier).getIdToken();
    if (token == null) return;

    try {
      final client = ref.read(apiClientProvider);
      await client.commentInDecisionRoom(
        token: token,
        roomId: widget.roomId,
        text: text,
      );
      
      // Track comment event
      final tracker = ref.read(eventTrackerProvider);
      tracker.track('decisionroom_comment', {
        'room': {'roomId': widget.roomId},
      });
      
      // Reload comments
      await _loadRoom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add comment: $e')),
        );
      }
    }
  }

  void _promptLogin() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign in required'),
        content: const Text('You need to sign in to vote and comment in Decision Rooms.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/auth/login', extra: '/r/${widget.roomId}');
            },
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareRoom() async {
    final baseUrl = Uri.base.origin;
    final shareUrl = '$baseUrl/r/${widget.roomId}';
    
    // For now, show a dialog with the URL
    // In production, use share_plus package
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Decision Room'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this link with friends:'),
            const SizedBox(height: AppTheme.spacingUnit),
            SelectableText(
              shareUrl,
              style: TextStyle(color: AppTheme.primaryAction),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSuggestDialog() async {
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated) {
      _promptLogin();
      return;
    }

    final urlController = TextEditingController();
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suggest alternative'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paste a link to a product you\'d like to suggest:'),
            const SizedBox(height: AppTheme.spacingUnit),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Product URL',
                hintText: 'https://...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, urlController.text.trim()),
            child: const Text('Suggest'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      await _suggestItem(result);
    }
  }

  Future<void> _suggestItem(String url) async {
    final token = await ref.read(authProvider.notifier).getIdToken();
    if (token == null) return;

    try {
      final client = ref.read(apiClientProvider);
      final result = await client.suggestInDecisionRoom(
        token: token,
        roomId: widget.roomId,
        url: url,
      );
      
      // Track suggest event
      final tracker = ref.read(eventTrackerProvider);
      tracker.track('suggest_alternative', {
        'room': {'roomId': widget.roomId},
        'item': {'itemId': result['itemId']},
        'ext': {'suggestedUrl': url},
      });
      
      await _loadRoom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alternative suggested!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to suggest: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Decision Room'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _roomData == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Decision Room'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppTheme.textCaption),
              const SizedBox(height: AppTheme.spacingUnit),
              Text(_error ?? 'Room not found', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppTheme.spacingUnit),
              ElevatedButton(
                onPressed: _loadRoom,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final title = _roomData!['title'] as String? ?? 'Decision Room';
    final status = _roomData!['status'] as String? ?? 'open';
    final items = (_roomData!['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final finalistIds = (_roomData!['finalistIds'] as List?)?.cast<String>() ?? [];
    final creatorUserId = _roomData!['creatorUserId'] as String?;
    final isCreator = authState.user?.uid == creatorUserId;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!authState.isAuthenticated)
            TextButton(
              onPressed: () => context.go('/auth/login', extra: '/r/${widget.roomId}'),
              child: const Text('Sign in'),
            ),
          // Suggest alternative button
          if (status == 'open')
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: 'Suggest alternative',
              onPressed: () => _showSuggestDialog(),
            ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share room',
            onPressed: () => _shareRoom(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status badge
          if (status == 'finalists')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              color: AppTheme.primaryAction.withOpacity(0.1),
              child: Text(
                'Final 2 selected! Vote for your favorite.',
                style: TextStyle(color: AppTheme.primaryAction, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),

          // Items grid
          Expanded(
            flex: 2,
            child: GridView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingUnit),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.75,
                crossAxisSpacing: AppTheme.spacingUnit,
                mainAxisSpacing: AppTheme.spacingUnit,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final itemId = item['id'] as String;
                final itemTitle = item['title'] as String? ?? 'Product';
                final images = (item['images'] as List?)?.cast<String>() ?? [];
                final imageUrl = images.isNotEmpty ? images.first : '';
                final voteCountUp = item['voteCountUp'] as int? ?? 0;
                final voteCountDown = item['voteCountDown'] as int? ?? 0;
                final isSuggested = item['isSuggested'] as bool? ?? false;
                final isFinalist = finalistIds.contains(itemId);

                return _ItemCard(
                  itemId: itemId,
                  title: itemTitle,
                  imageUrl: imageUrl,
                  voteCountUp: voteCountUp,
                  voteCountDown: voteCountDown,
                  isSuggested: isSuggested,
                  isFinalist: isFinalist,
                  onVoteUp: () => _vote(itemId, 'up'),
                  onVoteDown: () => _vote(itemId, 'down'),
                );
              },
            ),
          ),

          // Comments section
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Comments header
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 20, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        'Comments (${_comments.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),

                // Comments list (limited to 3)
                if (_comments.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _comments.length > 3 ? 3 : _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        final text = comment['text'] as String? ?? '';
                        final displayName = comment['displayName'] as String? ?? 'Anonymous';
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(displayName[0].toUpperCase()),
                          ),
                          title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(text),
                        );
                      },
                    ),
                  ),

                // Comment input
                Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingUnit),
                  child: _CommentInput(
                    onSubmit: _addComment,
                    enabled: authState.isAuthenticated,
                    onTapWhenDisabled: _promptLogin,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // Finalists button for creator
      floatingActionButton: isCreator && status == 'open'
          ? FloatingActionButton.extended(
              onPressed: () => _showFinalistsDialog(items),
              icon: const Icon(Icons.emoji_events),
              label: const Text('Pick finalists'),
            )
          : null,
    );
  }

  Future<void> _showFinalistsDialog(List<Map<String, dynamic>> items) async {
    final selected = <String>[];
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pick 2 finalists'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final itemId = item['id'] as String;
                final title = item['title'] as String? ?? 'Product';
                final isSelected = selected.contains(itemId);

                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true && selected.length < 2) {
                        selected.add(itemId);
                      } else if (value == false) {
                        selected.remove(itemId);
                      }
                    });
                  },
                  title: Text(title),
                  enabled: isSelected || selected.length < 2,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected.length == 2
                  ? () async {
                      Navigator.pop(context);
                      await _setFinalists(selected);
                    }
                  : null,
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setFinalists(List<String> finalistIds) async {
    final token = await ref.read(authProvider.notifier).getIdToken();
    if (token == null) return;

    try {
      final client = ref.read(apiClientProvider);
      await client.setDecisionRoomFinalists(
        token: token,
        roomId: widget.roomId,
        finalistIds: finalistIds,
      );
      
      // Track finalists set event
      final tracker = ref.read(eventTrackerProvider);
      tracker.track('finalists_set', {
        'room': {'roomId': widget.roomId},
        'finalists': finalistIds.map((id) => {'itemId': id}).toList(),
      });
      
      await _loadRoom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set finalists: $e')),
        );
      }
    }
  }
}

/// Item card widget for the grid.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.itemId,
    required this.title,
    required this.imageUrl,
    required this.voteCountUp,
    required this.voteCountDown,
    required this.isSuggested,
    required this.isFinalist,
    required this.onVoteUp,
    required this.onVoteDown,
  });

  final String itemId;
  final String title;
  final String imageUrl;
  final int voteCountUp;
  final int voteCountDown;
  final bool isSuggested;
  final bool isFinalist;
  final VoidCallback onVoteUp;
  final VoidCallback onVoteDown;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: isFinalist
            ? BorderSide(color: AppTheme.primaryAction, width: 2)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  Image.network(
                    ApiClient.proxyImageUrl(imageUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppTheme.background,
                      child: const Icon(Icons.image_not_supported),
                    ),
                  )
                else
                  Container(
                    color: AppTheme.background,
                    child: const Icon(Icons.weekend),
                  ),
                // Badges
                Positioned(
                  top: 8,
                  left: 8,
                  child: Row(
                    children: [
                      if (isFinalist)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAction,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Finalist',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (isSuggested) ...[
                        if (isFinalist) const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Suggested',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Title and votes
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onVoteUp,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.positiveLike.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.thumb_up, size: 16, color: AppTheme.positiveLike),
                              const SizedBox(width: 4),
                              Text('$voteCountUp', style: TextStyle(color: AppTheme.positiveLike)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: onVoteDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.negativeDislike.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.thumb_down, size: 16, color: AppTheme.negativeDislike),
                              const SizedBox(width: 4),
                              Text('$voteCountDown', style: TextStyle(color: AppTheme.negativeDislike)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Comment input widget.
class _CommentInput extends StatefulWidget {
  const _CommentInput({
    required this.onSubmit,
    required this.enabled,
    this.onTapWhenDisabled,
  });

  final Function(String) onSubmit;
  final bool enabled;
  final VoidCallback? onTapWhenDisabled;

  @override
  State<_CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends State<_CommentInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.enabled) {
      widget.onTapWhenDisabled?.call();
      return;
    }
    
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.enabled ? 'Add a comment...' : 'Sign in to comment',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              ),
            ),
            onTap: widget.enabled ? null : widget.onTapWhenDisabled,
            readOnly: !widget.enabled,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _submit,
          icon: Icon(Icons.send, color: AppTheme.primaryAction),
        ),
      ],
    );
  }
}
