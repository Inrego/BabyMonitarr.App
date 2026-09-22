import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cast_device.dart';
import '../models/room.dart';
import '../providers/cast_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Multi-select target picker for casting one room to displays and speakers.
///
/// Selection starts from whatever is already casting the room, falling back to the
/// room's saved default targets, so the common case is one tap on "Cast".
Future<void> showCastTargetSheet(BuildContext context, Room room) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CastTargetSheet(room: room),
  );
}

class CastTargetSheet extends StatefulWidget {
  final Room room;

  const CastTargetSheet({super.key, required this.room});

  @override
  State<CastTargetSheet> createState() => _CastTargetSheetState();
}

class _CastTargetSheetState extends State<CastTargetSheet> {
  final Set<String> _selected = <String>{};
  bool _hydrated = false;
  bool _busy = false;
  bool _saveAsDefault = false;

  Room get room => widget.room;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  Future<void> _hydrate() async {
    final cast = context.read<CastProvider>();
    await cast.refreshDevices();
    final saved = await cast.loadRoomTargets(room.id);
    if (!mounted) return;

    final casting = cast
        .devicesCastingRoom(room.id)
        .map((d) => d.deviceId)
        .toSet();

    setState(() {
      _selected
        ..clear()
        ..addAll(casting.isNotEmpty ? casting : saved);
      _hydrated = true;
    });
  }

  Future<void> _apply() async {
    final cast = context.read<CastProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final casting = cast
        .devicesCastingRoom(room.id)
        .map((d) => d.deviceId)
        .toSet();
    final toStop = casting.difference(_selected).toList(growable: false);
    final toStart = _selected.toList(growable: false);

    setState(() => _busy = true);
    try {
      if (toStop.isNotEmpty) {
        await cast.stopCast(room.id, deviceIds: toStop);
      }

      CastStartResult? result;
      if (toStart.isNotEmpty) {
        result = await cast.startCast(room.id, toStart);
      }

      if (_saveAsDefault) {
        await cast.saveRoomTargets(room.id, toStart);
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      if (result != null && result.hasFailures) {
        messenger.showSnackBar(
          SnackBar(content: Text(result.failed.values.first)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopAll() async {
    final cast = context.read<CastProvider>();
    setState(() => _busy = true);
    try {
      await cast.stopCast(room.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cast = context.watch<CastProvider>();
    final displays = cast.displays;
    final speakers = cast.speakers;
    final anyCasting = cast.isRoomCasting(room.id);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(cast),
            const SizedBox(height: 8),
            if (!_hydrated || cast.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (displays.isEmpty && speakers.isEmpty)
              _buildEmptyState(cast)
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (displays.isNotEmpty) ...[
                      _sectionLabel('Displays'),
                      ...displays.map(_deviceTile),
                    ],
                    if (speakers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _sectionLabel('Speakers'),
                      ...speakers.map(_deviceTile),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _saveAsDefault,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _saveAsDefault = value ?? false),
              title: Text(
                'Remember these targets for ${room.name}',
                style: AppTheme.caption,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (anyCasting)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _stopAll,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Stop all'),
                    ),
                  ),
                if (anyCasting) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || !_hydrated ? null : _apply,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryWarm,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.cast_connected, size: 18),
                    label: Text(_selected.isEmpty ? 'Stop casting' : 'Cast'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(CastProvider cast) {
    return Row(
      children: [
        Expanded(child: Text('Cast ${room.name}', style: AppTheme.subtitle)),
        IconButton(
          tooltip: 'Add by IP address',
          onPressed: _busy ? null : _promptForAddress,
          icon: const Icon(Icons.add_link, color: AppColors.textSecondary),
        ),
        IconButton(
          tooltip: 'Scan for devices',
          onPressed: cast.isScanning || _busy ? null : cast.scanForDevices,
          icon: cast.isScanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildEmptyState(CastProvider cast) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.cast, size: 36, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            'No cast devices found on the network.',
            style: AppTheme.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'The server discovers devices over mDNS. In Docker that needs host '
            'networking — otherwise add a device by IP.',
            style: AppTheme.caption,
            textAlign: TextAlign.center,
          ),
          if (cast.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              cast.lastError!,
              style: AppTheme.caption.copyWith(color: AppColors.secondaryWarm),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: AppTheme.caption.copyWith(
        color: AppColors.primaryWarm,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _deviceTile(CastDevice device) {
    final selected = _selected.contains(device.deviceId);
    final castingOtherRoom =
        device.castingRoomId != null && device.castingRoomId != room.id;

    final subtitleParts = <String>[
      if (device.model.isNotEmpty) device.model,
      if (device.isGroup) 'Group',
      if (!device.isOnline) 'Offline',
      if (castingOtherRoom) 'Casting another room',
      if (device.lastError != null) device.lastError!,
    ];

    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: selected,
      onChanged: _busy
          ? null
          : (value) => setState(() {
              if (value ?? false) {
                _selected.add(device.deviceId);
              } else {
                _selected.remove(device.deviceId);
              }
            }),
      secondary: Icon(
        device.isGroup
            ? Icons.speaker_group
            : (device.isVideoCapable ? Icons.tv : Icons.speaker),
        color: device.isOnline
            ? AppColors.textPrimary
            : AppColors.textSecondary,
      ),
      title: Text(
        device.name.isEmpty ? device.host : device.name,
        style: AppTheme.body.copyWith(color: AppColors.textPrimary),
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(subtitleParts.join(' • '), style: AppTheme.caption),
    );
  }

  Future<void> _promptForAddress() async {
    final hostController = TextEditingController();
    bool isVideoCapable = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Add cast device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'IP address or hostname',
                  hintText: '192.168.0.42',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Has a screen', style: AppTheme.caption),
                value: isVideoCapable,
                onChanged: (value) =>
                    setDialogState(() => isVideoCapable = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final host = hostController.text.trim();
    if (host.isEmpty) return;

    final cast = context.read<CastProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final added = await cast.addDeviceByAddress(
      host: host,
      isVideoCapable: isVideoCapable,
    );

    if (!added && mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(cast.lastError ?? 'Could not reach $host')),
      );
    }
  }
}
