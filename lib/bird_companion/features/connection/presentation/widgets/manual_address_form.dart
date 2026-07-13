import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class ManualAddressForm extends StatefulWidget {
  const ManualAddressForm({super.key, required this.onConnect, this.isSubmitting = false, this.initialAddress});

  final ValueChanged<Uri> onConnect;
  final bool isSubmitting;
  final Uri? initialAddress;

  @override
  State<ManualAddressForm> createState() => _ManualAddressFormState();
}

class _ManualAddressFormState extends State<ManualAddressForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: widget.initialAddress?.toString() ?? 'http://192.168.4.1:8080');
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    var raw = _addressController.text.trim();
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) raw = 'http://$raw';
    widget.onConnect(Uri.parse(raw));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('输入盒子的本地服务地址，例如热点默认地址或局域网 IP。', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _addressController,
            keyboardType: TextInputType.url,
            enabled: !widget.isSubmitting,
            decoration: const InputDecoration(labelText: '盒子地址', hintText: 'http://192.168.4.1:8080'),
            validator: (value) {
              var raw = value?.trim() ?? '';
              if (raw.isEmpty) return '请输入盒子地址';
              if (!raw.startsWith('http://') && !raw.startsWith('https://')) raw = 'http://$raw';
              final uri = Uri.tryParse(raw);
              if (uri == null || uri.host.isEmpty) return '请输入有效的 IP 或主机名';
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: widget.isSubmitting ? null : _submit,
            icon: widget.isSubmitting ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
            label: Text(widget.isSubmitting ? '正在连接…' : '连接盒子'),
          ),
        ],
      ),
    );
  }
}
