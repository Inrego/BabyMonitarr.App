import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audio_settings.dart';
import '../models/global_settings.dart';
import '../models/nest_device.dart';
import '../models/room.dart';
import '../providers/connection_provider.dart';
import '../providers/room_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/room_icons.dart';
import '../widgets/server_url_dialog.dart';

class MonitorSettingsScreen extends StatefulWidget {
  final int? initialRoomId;

  const MonitorSettingsScreen({super.key, this.initialRoomId});

  @override
  State<MonitorSettingsScreen> createState() => _MonitorSettingsScreenState();
}

class _MonitorSettingsScreenState extends State<MonitorSettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cameraUrlController = TextEditingController();
  final TextEditingController _thresholdController = TextEditingController();
  final TextEditingController _highPassController = TextEditingController();
  final TextEditingController _lowPassController = TextEditingController();

  final List<String> _icons = const [
    'baby',
    'baby-carriage',
    'bed',
    'moon',
    'star',
    'heart',
    'home',
    'door-open',
  ];

  int? _hydratedRoomId;
  String _selectedIcon = 'baby';
  String _monitorType = 'camera_audio';
  bool _enableVideo = false;
  bool _enableAudio = true;
  String _streamSourceType = 'rtsp';
  String? _nestDeviceId;
  bool _nestLinked = true;
  bool _loadingNestDevices = false;
  List<NestDevice> _nestDevices = const <NestDevice>[];
  bool _filterEnabled = false;
  bool _saving = false;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final connection = context.read<ConnectionProvider>();
    final rooms = context.read<RoomProvider>();
    rooms.bindConnection(connection);

    final url = settings.serverUrl;
    if (url != null && url.isNotEmpty && !connection.isConnected) {
      try {
        await connection.connect(url);
      } catch (_) {}
    }
    if (connection.isConnected) {
      await rooms.refreshAll();
      await _refreshNestIntegration(force: true);
    }

    final initialId = widget.initialRoomId ?? rooms.activeRoom?.id;
    if (initialId != null && rooms.roomById(initialId) != null) {
      rooms.setEditingRoomId(initialId);
    } else if (rooms.editingRoomId == null && rooms.rooms.isNotEmpty) {
      rooms.setEditingRoomId(rooms.rooms.first.id);
    }

    _hydrateFromProvider(force: true);
    _bootstrapped = true;
    if (mounted) setState(() {});
  }

  void _hydrateFromProvider({bool force = false}) {
    final roomProvider = context.read<RoomProvider>();
    final room = roomProvider.editingRoom;
    if (room == null) return;
    if (!force && _hydratedRoomId == room.id) return;

    final global = roomProvider.globalSettings;
    _hydratedRoomId = room.id;
    _nameController.text = room.name;
    _cameraUrlController.text = room.cameraStreamUrl ?? '';
    _selectedIcon = room.icon;
    _monitorType = room.monitorType;
    _enableVideo = room.enableVideoStream;
    _enableAudio = room.enableAudioStream;
    _streamSourceType = room.streamSourceType;
    _nestDeviceId = room.nestDeviceId;
    _filterEnabled = global.filterEnabled;
    _thresholdController.text = global.soundThreshold.toStringAsFixed(1);
    _highPassController.text = global.highPassFrequency.toString();
    _lowPassController.text = global.lowPassFrequency.toString();

    if (_streamSourceType == 'google_nest') {
      unawaited(_refreshNestIntegration());
    }
  }

  Future<void> _addMonitor() async {
    final roomProvider = context.read<RoomProvider>();
    final room = await roomProvider.createRoom();
    if (room == null) return;
    roomProvider.setEditingRoomId(room.id);
    _hydrateFromProvider(force: true);
    if (mounted) setState(() {});
  }

  Future<void> _activateMonitor() async {
    final roomProvider = context.read<RoomProvider>();
    final room = roomProvider.editingRoom;
    if (room == null) return;
    await roomProvider.selectRoomForMonitoring(room.id);
    await roomProvider.refreshRooms();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Now monitoring ${room.name}')));
  }

  Future<void> _save() async {
    final roomProvider = context.read<RoomProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final room = roomProvider.editingRoom;
    if (room == null || _saving) return;

    setState(() => _saving = true);
    try {
      final updatedRoom = room.copyWith(
        name: _nameController.text.trim().isEmpty
            ? 'Unnamed Monitor'
            : _nameController.text.trim(),
        icon: _selectedIcon,
        monitorType: _monitorType,
        enableVideoStream: _enableVideo,
        enableAudioStream: _enableAudio,
        streamSourceType: _streamSourceType,
        nestDeviceId: _streamSourceType == 'google_nest' ? _nestDeviceId : '',
        cameraStreamUrl: _streamSourceType == 'rtsp'
            ? _cameraUrlController.text.trim()
            : '',
      );

      final global = roomProvider.globalSettings.copyWith(
        soundThreshold: _parseDouble(_thresholdController.text, -20.0),
        highPassFrequency: _parseInt(_highPassController.text, 300),
        lowPassFrequency: _parseInt(_lowPassController.text, 4000),
        filterEnabled: _filterEnabled,
      );

      await roomProvider.saveRoomAndGlobalSettings(updatedRoom, global);
      settingsProvider.updateAudioSettings(
        _mergeGlobalIntoAudioSettings(settingsProvider.audioSettings, global),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuration saved')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final roomProvider = context.read<RoomProvider>();
    final room = roomProvider.editingRoom;
    if (room == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete monitor?', style: AppTheme.subtitle),
        content: Text(
          'Delete "${room.name}" permanently?',
          style: AppTheme.body.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.secondaryWarm),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final deleted = await roomProvider.deleteRoom(room.id);
    if (!deleted) return;

    if (roomProvider.rooms.isNotEmpty) {
      roomProvider.setEditingRoomId(roomProvider.rooms.first.id);
    }
    _hydratedRoomId = null;
    _hydrateFromProvider(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Monitor deleted')));
  }

  Future<void> _changeServerUrl() async {
    final settings = context.read<SettingsProvider>();
    final connection = context.read<ConnectionProvider>();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => ServerUrlDialog(currentUrl: settings.serverUrl),
    );
    if (url == null || url.isEmpty) return;
    await settings.setServerUrl(url);
    await connection.connect(url);
    if (!mounted) return;
    await context.read<RoomProvider>().refreshAll();
    await _refreshNestIntegration(force: true);
  }

  Future<void> _refreshNestIntegration({bool force = false}) async {
    if (_streamSourceType != 'google_nest' && !force) return;

    final connection = context.read<ConnectionProvider>();
    if (!connection.isConnected || _loadingNestDevices) return;

    setState(() => _loadingNestDevices = true);
    try {
      final isLinked = await connection.signalR.isNestLinked();
      final devices = isLinked
          ? await connection.signalR.getNestDevices()
          : const <NestDevice>[];
      if (!mounted) return;
      setState(() {
        _nestLinked = isLinked;
        _nestDevices = devices;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nestLinked = false;
        _nestDevices = const <NestDevice>[];
      });
    } finally {
      if (mounted) {
        setState(() => _loadingNestDevices = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cameraUrlController.dispose();
    _thresholdController.dispose();
    _highPassController.dispose();
    _lowPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomProvider = context.watch<RoomProvider>();
    final connection = context.watch<ConnectionProvider>();
    final settings = context.watch<SettingsProvider>();
    _hydrateFromProvider();

    final room = roomProvider.editingRoom;
    final rooms = roomProvider.rooms;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('Monitor Settings', style: AppTheme.subtitle),
        actions: [
          IconButton(onPressed: _addMonitor, icon: const Icon(Icons.add)),
        ],
      ),
      body: !_bootstrapped
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
              children: [
                _buildRoomSelector(rooms, roomProvider),
                const SizedBox(height: 14),
                if (room == null) _buildNoRoomCard(),
                if (room != null) ...[
                  _sectionCard(
                    title: 'Monitor Details',
                    children: [
                      _inputLabel('Monitor Name'),
                      _textField(_nameController, hint: "Baby's Room"),
                      const SizedBox(height: 12),
                      _inputLabel('Monitor Type'),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_monitorType),
                        initialValue: _monitorType,
                        dropdownColor: AppColors.surface,
                        decoration: _inputDecoration(),
                        items: const [
                          DropdownMenuItem(
                            value: 'camera_audio',
                            child: Text('Camera with Audio'),
                          ),
                          DropdownMenuItem(
                            value: 'audio_only',
                            child: Text('Audio Only'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _monitorType = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      _inputLabel('Room Icon'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _icons
                            .map((icon) {
                              final selected = _selectedIcon == icon;
                              return InkWell(
                                onTap: () =>
                                    setState(() => _selectedIcon = icon),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: selected
                                        ? AppColors.primaryWarm.withValues(
                                            alpha: 0.18,
                                          )
                                        : AppColors.surface,
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primaryWarm
                                          : AppColors.surfaceLight,
                                    ),
                                  ),
                                  child: Icon(
                                    _iconForRoom(icon),
                                    color: selected
                                        ? AppColors.primaryWarm
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tealAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          room.isActive ? 'Connected' : 'Not active',
                          style: AppTheme.caption.copyWith(
                            color: AppColors.tealAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Connection',
                    children: [
                      _inputLabel('Server URL'),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              settings.serverUrl ?? 'Not configured',
                              style: AppTheme.body.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _changeServerUrl,
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _enableVideo,
                        onChanged: (value) =>
                            setState(() => _enableVideo = value),
                        title: Text(
                          'Enable Video Stream',
                          style: AppTheme.body.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.primaryWarm,
                      ),
                      SwitchListTile(
                        value: _enableAudio,
                        onChanged: (value) =>
                            setState(() => _enableAudio = value),
                        title: Text(
                          'Enable Audio Stream',
                          style: AppTheme.body.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.primaryWarm,
                      ),
                      const SizedBox(height: 8),
                      _inputLabel('Stream Source'),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_streamSourceType),
                        initialValue: _streamSourceType,
                        dropdownColor: AppColors.surface,
                        decoration: _inputDecoration(),
                        items: const [
                          DropdownMenuItem(
                            value: 'rtsp',
                            child: Text('RTSP Camera'),
                          ),
                          DropdownMenuItem(
                            value: 'google_nest',
                            child: Text('Google Nest Camera'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _streamSourceType = value);
                          if (value == 'google_nest') {
                            unawaited(_refreshNestIntegration(force: true));
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      if (_streamSourceType == 'rtsp') ...[
                        _inputLabel('Monitor Address'),
                        _textField(
                          _cameraUrlController,
                          hint: 'rtsp://192.168.1.100:554/stream',
                        ),
                      ] else ...[
                        if (!_nestLinked)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryWarm.withValues(
                                alpha: 0.16,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Google Nest account is not linked on the backend.',
                              style: AppTheme.caption.copyWith(
                                color: AppColors.secondaryWarm,
                              ),
                            ),
                          ),
                        _inputLabel('Nest Camera'),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            '${_nestDeviceId ?? ''}-${_nestDevices.length}',
                          ),
                          initialValue: (_nestDeviceId?.isNotEmpty ?? false)
                              ? _nestDeviceId
                              : '',
                          dropdownColor: AppColors.surface,
                          decoration: _inputDecoration(),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Select a Nest camera...'),
                            ),
                            ..._nestDevices.map(
                              (device) => DropdownMenuItem(
                                value: device.deviceId,
                                child: Text(device.label),
                              ),
                            ),
                            if ((_nestDeviceId?.isNotEmpty ?? false) &&
                                !_nestDevices.any(
                                  (device) => device.deviceId == _nestDeviceId,
                                ))
                              DropdownMenuItem(
                                value: _nestDeviceId!,
                                child: Text(_nestDeviceId!),
                              ),
                          ],
                          onChanged: _loadingNestDevices
                              ? null
                              : (value) {
                                  setState(() {
                                    _nestDeviceId =
                                        (value == null || value.isEmpty)
                                        ? null
                                        : value;
                                  });
                                },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _loadingNestDevices
                                  ? null
                                  : () => _refreshNestIntegration(force: true),
                              child: const Text('Refresh Nest Cameras'),
                            ),
                            if (_loadingNestDevices) ...[
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Audio Processing',
                    children: [
                      _inputLabel('Sound Threshold (dB)'),
                      _textField(
                        _thresholdController,
                        hint: '-20',
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _filterEnabled,
                        onChanged: (value) =>
                            setState(() => _filterEnabled = value),
                        title: Text(
                          'Enable Audio Filters',
                          style: AppTheme.body.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.primaryWarm,
                      ),
                      const SizedBox(height: 10),
                      _inputLabel('High Pass (Hz)'),
                      _textField(
                        _highPassController,
                        hint: '300',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      _inputLabel('Low Pass (Hz)'),
                      _textField(
                        _lowPassController,
                        hint: '4000',
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Actions',
                    children: [
                      _actionButton(
                        label: 'Save Configuration',
                        icon: Icons.save_outlined,
                        active: true,
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                      const SizedBox(height: 10),
                      _actionButton(
                        label: 'Activate Monitor',
                        icon: Icons.play_arrow,
                        active: room.isActive,
                        onPressed: _activateMonitor,
                      ),
                      const SizedBox(height: 10),
                      _actionButton(
                        label: 'Delete Monitor',
                        icon: Icons.delete_outline,
                        danger: true,
                        onPressed: _delete,
                      ),
                    ],
                  ),
                  if (!connection.isConnected) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Disconnected from server. Changes cannot be saved.',
                      style: AppTheme.caption.copyWith(
                        color: AppColors.secondaryWarm,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _buildRoomSelector(List<Room> rooms, RoomProvider provider) {
    final selected = provider.editingRoom;
    return InkWell(
      onTap: rooms.isEmpty
          ? null
          : () async {
              final selectedId = await showModalBottomSheet<int>(
                context: context,
                backgroundColor: AppColors.surface,
                builder: (_) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: rooms
                        .map(
                          (room) => ListTile(
                            leading: Icon(_iconForRoom(room.icon)),
                            title: Text(room.name),
                            trailing: room.id == provider.editingRoomId
                                ? const Icon(
                                    Icons.check,
                                    color: AppColors.primaryWarm,
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(room.id),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              );
              if (selectedId != null) {
                provider.setEditingRoomId(selectedId);
                _hydratedRoomId = null;
                if (mounted) setState(() {});
              }
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryWarm.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                selected == null ? Icons.videocam : _iconForRoom(selected.icon),
                color: AppColors.primaryWarm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected?.name ?? 'Select monitor',
                style: AppTheme.subtitle.copyWith(fontSize: 24),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildNoRoomCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.videocam_off,
            size: 32,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text('No monitors configured', style: AppTheme.subtitle),
          const SizedBox(height: 6),
          Text(
            'Add a monitor to configure stream and audio settings.',
            style: AppTheme.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _addMonitor,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryWarm,
              foregroundColor: AppColors.background,
            ),
            child: const Text('Add Monitor'),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.subtitle.copyWith(fontSize: 22)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _inputLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppTheme.caption.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller, {
    required String hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: AppTheme.body.copyWith(color: AppColors.textPrimary),
      decoration: _inputDecoration(hintText: hint),
    );
  }

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTheme.caption,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryWarm),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    bool active = false,
    bool danger = false,
    bool loading = false,
    required VoidCallback? onPressed,
  }) {
    final bg = danger
        ? AppColors.secondaryWarm.withValues(alpha: 0.2)
        : active
        ? AppColors.primaryWarm
        : AppColors.surface;
    final fg = danger
        ? AppColors.secondaryWarm
        : active
        ? AppColors.background
        : AppColors.primaryWarm;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(label, style: AppTheme.body.copyWith(color: fg)),
      ),
    );
  }

  int _parseInt(String value, int fallback) => int.tryParse(value) ?? fallback;

  double _parseDouble(String value, double fallback) =>
      double.tryParse(value) ?? fallback;

  AudioSettings _mergeGlobalIntoAudioSettings(
    AudioSettings base,
    GlobalSettings global,
  ) {
    return base.copyWith(
      soundThreshold: global.soundThreshold,
      averageSampleCount: global.averageSampleCount,
      filterEnabled: global.filterEnabled,
      lowPassFrequency: global.lowPassFrequency,
      highPassFrequency: global.highPassFrequency,
      thresholdPauseDuration: global.thresholdPauseDuration,
      volumeAdjustmentDb: global.volumeAdjustmentDb,
    );
  }

  IconData _iconForRoom(String icon) => iconForRoom(icon);
}
