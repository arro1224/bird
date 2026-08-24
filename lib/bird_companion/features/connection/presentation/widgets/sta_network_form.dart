import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/material.dart';

class StaNetworkForm extends StatefulWidget {
  const StaNetworkForm({
    super.key,
    required this.onSubmit,
    this.selectedNetwork,
  });

  final WifiScanNetwork? selectedNetwork;
  final ValueChanged<StaNetworkConfiguration> onSubmit;

  @override
  State<StaNetworkForm> createState() => _StaNetworkFormState();
}

class _StaNetworkFormState extends State<StaNetworkForm> {
  late final TextEditingController _ssidController;
  final TextEditingController _passwordController = TextEditingController();
  late WifiSecurity _security;
  var _hidden = false;
  var _networkKind = StaNetworkKind.router;
  String? _ssidError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _ssidController = TextEditingController(text: widget.selectedNetwork?.ssid);
    _security = widget.selectedNetwork?.security ?? WifiSecurity.wpa2Personal;
  }

  @override
  void dispose() {
    _passwordController.clear();
    _passwordController.dispose();
    _ssidController.dispose();
    super.dispose();
  }

  void _submit() {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;
    final secured = _security != WifiSecurity.open;
    setState(() {
      _ssidError = ssid.isEmpty ? '请输入 Wi-Fi 名称' : null;
      _passwordError = secured && password.isEmpty ? '请输入 Wi-Fi 密码' : null;
    });
    if (_ssidError != null || _passwordError != null) return;

    final selected = widget.selectedNetwork;
    widget.onSubmit(
      StaNetworkConfiguration(
        provisioningMethod: selected == null ? ProvisioningMethod.bleManual : ProvisioningMethod.bleScanSelection,
        selectionMethod: selected == null ? WifiSelectionMethod.manual : WifiSelectionMethod.scanResult,
        ssid: ssid,
        bssid: selected?.bssid,
        security: _security,
        password: secured ? password : null,
        hidden: selected == null && _hidden,
        networkKind: _networkKind,
      ),
    );
    _passwordController.clear();
    setState(() => _passwordError = null);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
    children: [
      Text(
        widget.selectedNetwork == null ? '手动加入 Wi-Fi' : '连接所选 Wi-Fi',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        key: const ValueKey('wifi-ssid'),
        controller: _ssidController,
        readOnly: widget.selectedNetwork != null,
        decoration: InputDecoration(
          labelText: 'Wi-Fi 名称',
          errorText: _ssidError,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      DropdownButtonFormField<WifiSecurity>(
        initialValue: _security,
        decoration: const InputDecoration(labelText: '安全类型'),
        items: WifiSecurity.values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(_securityLabel(value)),
              ),
            )
            .toList(),
        onChanged: widget.selectedNetwork == null
            ? (value) => setState(() {
                _security = value ?? _security;
                if (_security == WifiSecurity.open) _passwordError = null;
              })
            : null,
      ),
      if (_security != WifiSecurity.open) ...[
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('wifi-password'),
          controller: _passwordController,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Wi-Fi 密码',
            errorText: _passwordError,
          ),
        ),
      ] else
        const SizedBox(key: ValueKey('wifi-password')),
      if (widget.selectedNetwork == null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('隐藏网络'),
          value: _hidden,
          onChanged: (value) => setState(() => _hidden = value),
        ),
      DropdownButtonFormField<StaNetworkKind>(
        initialValue: _networkKind,
        decoration: const InputDecoration(labelText: '网络类型'),
        items: StaNetworkKind.values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(_networkKindLabel(value)),
              ),
            )
            .toList(),
        onChanged: (value) => setState(
          () => _networkKind = value ?? _networkKind,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      BirdButton(
        label: '连接此 Wi-Fi',
        onPressed: _submit,
        icon: const Icon(Icons.wifi_rounded),
      ),
    ],
  );
}

String _securityLabel(WifiSecurity security) => switch (security) {
  WifiSecurity.open => '开放网络',
  WifiSecurity.wpa2Personal => 'WPA2',
  WifiSecurity.wpa3Personal => 'WPA3',
  WifiSecurity.wpa2Wpa3Transition => 'WPA2/WPA3',
};

String _networkKindLabel(StaNetworkKind kind) => switch (kind) {
  StaNetworkKind.router => '路由器',
  StaNetworkKind.thisPhoneHotspot => '本机热点',
  StaNetworkKind.otherPhoneHotspot => '其他手机热点',
  StaNetworkKind.unknown => '其他网络',
};
