import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class ServerUrlDialog extends StatefulWidget {
  final String? currentUrl;

  const ServerUrlDialog({super.key, this.currentUrl});

  @override
  State<ServerUrlDialog> createState() => _ServerUrlDialogState();
}

class _ServerUrlDialogState extends State<ServerUrlDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    if (value.trim().isEmpty) return 'URL is required';
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Enter a valid URL (e.g. http://192.168.1.100:5148)';
    }
    return null;
  }

  void _submit() {
    final error = _validate(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    var url = _controller.text.trim();
    if (!url.endsWith('/audioHub')) {
      url = url.endsWith('/') ? '${url}audioHub' : '$url/audioHub';
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Server URL', style: AppTheme.subtitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            style: AppTheme.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'http://192.168.1.100:5148',
              hintStyle: AppTheme.caption,
              errorText: _error,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            '/audioHub will be appended automatically',
            style: AppTheme.caption,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: AppTheme.body.copyWith(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Connect',
              style: AppTheme.body.copyWith(color: AppColors.primaryWarm)),
        ),
      ],
    );
  }
}
