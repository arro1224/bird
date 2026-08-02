import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:flutter/material.dart';

class PairingCodeForm extends StatefulWidget {
  const PairingCodeForm({
    super.key,
    required this.deviceName,
    required this.onSubmit,
    required this.onCancel,
  });

  final String deviceName;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<PairingCodeForm> createState() => _PairingCodeFormState();
}

class _PairingCodeFormState extends State<PairingCodeForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
    children: [
      const SizedBox(height: AppSpacing.xl),
      const Icon(Icons.phonelink_lock_rounded, size: 72),
      const SizedBox(height: AppSpacing.lg),
      Text(
        '与 ${widget.deviceName} 配对',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        '请输入盒子屏幕上显示的配对码。配对成功后，访问凭据只会加密保存在本机。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: AppSpacing.lg),
      TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: '配对码',
          hintText: '至少 4 位',
          prefixIcon: Icon(Icons.password_rounded),
        ),
        onSubmitted: _submit,
      ),
      const SizedBox(height: AppSpacing.lg),
      BirdButton(
        label: '安全配对并连接',
        onPressed: () => _submit(_controller.text),
        icon: const Icon(Icons.lock_open_rounded),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextButton(onPressed: widget.onCancel, child: const Text('取消')),
    ],
  );

  void _submit(String value) {
    final code = value.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入至少 4 位配对码。')),
      );
      return;
    }
    widget.onSubmit(code);
  }
}
