import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

class SyncedLyrics extends StatefulWidget {
  const SyncedLyrics({
    super.key,
    required this.lines,
    required this.position,
    required this.realtime,
    required this.seekable,
    required this.onSeek,
    this.offsetMs = 0,
    this.onOffsetChanged,
  });
  final List<Map<String, dynamic>> lines;
  final double position;
  final bool realtime;
  final bool seekable;
  final ValueChanged<double> onSeek;
  final int offsetMs;
  final ValueChanged<int>? onOffsetChanged;
  @override
  State<SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<SyncedLyrics> {
  final _scroll = ScrollController();
  List<GlobalKey> _keys = [];
  int _lastLine = -1;
  bool _follow = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_keys.length != widget.lines.length) {
      _keys = List.generate(widget.lines.length, (_) => GlobalKey());
      _lastLine = -1;
    }
    // Untimed lyrics and live streams have no reliable playback timebase.
    final synced =
        !widget.realtime &&
        widget.lines.any(
          (line) => ((line['start'] as num?)?.toDouble() ?? 0) > 0,
        );
    var active = -1;
    if (synced) {
      for (var i = 0; i < widget.lines.length; i++) {
        if (((widget.lines[i]['start'] as num?)?.toDouble() ?? 0) <=
            widget.position + widget.offsetMs / 1000) {
          active = i;
        }
      }
    }
    if (synced && _follow && active >= 0 && active != _lastLine) {
      _lastLine = active;
      final key = _keys[active];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final lineContext = key.currentContext;
        if (mounted && lineContext != null) {
          Scrollable.ensureVisible(
            lineContext,
            duration: const Duration(milliseconds: 350),
            alignment: .4,
            curve: Curves.easeOut,
          );
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  synced
                      ? 'Synced lyrics · select a line to seek'
                      : widget.realtime
                      ? 'Live stream · lyrics shown without timing'
                      : 'Lyrics',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (synced && widget.onOffsetChanged != null) ...[
                IconButton(
                  tooltip: 'Delay lyrics 250 ms',
                  onPressed: widget.offsetMs <= -10000
                      ? null
                      : () => widget.onOffsetChanged!(
                          (widget.offsetMs - 250).clamp(-10000, 10000),
                        ),
                  icon: const Icon(Icons.remove, size: 16),
                ),
                Text(
                  '${widget.offsetMs >= 0 ? '+' : ''}${widget.offsetMs} ms',
                  style: const TextStyle(fontSize: 11),
                ),
                IconButton(
                  tooltip: 'Advance lyrics 250 ms',
                  onPressed: widget.offsetMs >= 10000
                      ? null
                      : () => widget.onOffsetChanged!(
                          (widget.offsetMs + 250).clamp(-10000, 10000),
                        ),
                  icon: const Icon(Icons.add, size: 16),
                ),
              ],
              if (synced)
                FilterChip(
                  label: const Text(
                    'Follow lyrics',
                    style: TextStyle(fontSize: 11),
                  ),
                  selected: _follow,
                  onSelected: (value) => setState(() {
                    _follow = value;
                    _lastLine = -1;
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (_follow && notification.direction != ScrollDirection.idle) {
                setState(() => _follow = false);
              }
              return false;
            },
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(48, 20, 48, 70),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.lines.length; i++)
                      Padding(
                        key: _keys[i],
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: InkWell(
                          onTap: synced && widget.seekable
                              ? () => widget.onSeek(
                                  (((widget.lines[i]['start'] as num?)
                                                  ?.toDouble() ??
                                              0) -
                                          widget.offsetMs / 1000)
                                      .clamp(0, double.infinity),
                                )
                              : null,
                          child: Text(
                            '${widget.lines[i]['text'] ?? ''}',
                            style: TextStyle(
                              fontSize: i == active ? 30 : 25,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              color: i == active
                                  ? Theme.of(context).colorScheme.primary
                                  : !synced
                                  ? Theme.of(context).colorScheme.onSurface
                                  : i < active
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
