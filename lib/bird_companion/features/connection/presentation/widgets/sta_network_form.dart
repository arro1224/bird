import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/data/platform/phone_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/material.dart';

enum WifiFormScanStatus { idle, scanning, complete, failed, cancelled }

/// Read-only refreshes update their evidence without replacing the user's draft.
class StaNetworkForm extends StatefulWidget {
  const StaNetworkForm({
    super.key,
    required this.onSubmit,
    this.selectedNetwork,
    this.initialSsid,
    this.initialHint,
    this.initialNetworkKind = StaNetworkKind.router,
    this.phoneWifi,
    this.readingPhoneWifi = false,
    this.onRefreshPhoneWifi,
    this.manualSupported = true,
    this.scanStatus = WifiFormScanStatus.idle,
    this.networks = const [],
    this.onScan,
    this.onCancelScan,
    this.savedNetwork,
  });

  final WifiScanNetwork? selectedNetwork;
  final String? initialSsid, initialHint;
  final StaNetworkKind initialNetworkKind;
  final PhoneWifiSsid? phoneWifi;
  final bool readingPhoneWifi, manualSupported;
  final VoidCallback? onRefreshPhoneWifi, onScan, onCancelScan;
  final WifiFormScanStatus scanStatus;
  final List<WifiScanNetwork> networks;
  final InfrastructureStaSnapshot? savedNetwork;
  final ValueChanged<StaNetworkConfiguration> onSubmit;

  @override
  State<StaNetworkForm> createState() => _StaNetworkFormState();
}

class _StaNetworkFormState extends State<StaNetworkForm> {
  late final TextEditingController _ssidController;
  final TextEditingController _passwordController = TextEditingController();
  late WifiSecurity _security;
  late StaNetworkKind _networkKind;
  WifiScanNetwork? _selected;
  PhoneWifiSsid? _nameEvidence;
  var _hidden = false;
  var _ssidEdited = false;
  var _editRevision = 0;
  var _phoneReadRevision = 0;
  String? _ssidError, _passwordError;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedNetwork;
    _networkKind = widget.initialNetworkKind;
    final phoneSsid = _networkKind == StaNetworkKind.thisPhoneHotspot ? null : widget.phoneWifi?.ssid;
    _ssidController = TextEditingController(text: _selected?.ssid ?? widget.initialSsid ?? phoneSsid);
    if (_selected == null && phoneSsid != null) _nameEvidence = widget.phoneWifi;
    _security = _selected?.security ?? WifiSecurity.wpa2Personal;
  }

  @override
  void didUpdateWidget(covariant StaNetworkForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.readingPhoneWifi && widget.readingPhoneWifi) _phoneReadRevision = _editRevision;
    if (widget.phoneWifi != oldWidget.phoneWifi &&
        widget.phoneWifi?.isReadable == true &&
        _networkKind != StaNetworkKind.thisPhoneHotspot &&
        _selected == null &&
        !_ssidEdited &&
        _phoneReadRevision == _editRevision &&
        _passwordController.text.isEmpty) {
      _ssidController.text = widget.phoneWifi!.ssid!;
      _nameEvidence = widget.phoneWifi;
    }
    if (widget.selectedNetwork != oldWidget.selectedNetwork && widget.selectedNetwork != null) _chooseNetwork(widget.selectedNetwork!);
  }

  @override
  void dispose() {
    _passwordController.clear();
    _passwordController.dispose();
    _ssidController.dispose();
    super.dispose();
  }

  void _clearPassword() {
    _passwordController.clear();
    _passwordError = null;
  }

  void _chooseNetwork(WifiScanNetwork network) {
    if (network.unsupported) return;
    final sameTarget = _selected?.bssid.toUpperCase() == network.bssid.toUpperCase() && _ssidController.text == network.ssid && _security == network.security;
    if (!sameTarget) _clearPassword();
    _selected = network;
    _nameEvidence = null;
    _ssidController.text = network.ssid;
    _security = network.security;
    _hidden = false;
    _ssidEdited = true;
    _ssidError = null;
    _editRevision++;
  }

  void _usePhoneName() => setState(() {
    if (_ssidController.text != widget.phoneWifi!.ssid || _selected != null) _clearPassword();
    _ssidController.text = widget.phoneWifi!.ssid!;
    _selected = null;
    _nameEvidence = widget.phoneWifi;
    _ssidEdited = true;
    _ssidError = null;
    _editRevision++;
  });

  void _changeKind(StaNetworkKind value) => setState(() {
    if (_networkKind == value) return;
    if (value == StaNetworkKind.thisPhoneHotspot && !_ssidEdited && _selected == null) {
      _ssidController.clear();
      _nameEvidence = null;
    }
    _networkKind = value;
    _clearPassword();
    _editRevision++;
  });

  void _submit() {
    if (widget.scanStatus == WifiFormScanStatus.scanning || (!widget.manualSupported && _selected == null)) return;
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;
    final secured = _security != WifiSecurity.open;
    setState(() {
      _ssidError = ssid.isEmpty ? '请输入 Wi-Fi 名称' : null;
      _passwordError = secured && password.isEmpty ? '请输入 Wi-Fi 密码' : null;
    });
    if (_ssidError != null || _passwordError != null) return;
    widget.onSubmit(
      StaNetworkConfiguration(
        provisioningMethod: _selected == null ? ProvisioningMethod.bleManual : ProvisioningMethod.bleScanSelection,
        selectionMethod: _selected == null ? WifiSelectionMethod.manual : WifiSelectionMethod.scanResult,
        ssid: ssid,
        bssid: _selected?.bssid,
        security: _security,
        password: secured ? password : null,
        hidden: _selected == null && _hidden,
        networkKind: _networkKind,
      ),
    );
    _clearPassword();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phoneWifi;
    final readAt = phone?.readAt?.toLocal();
    final readTime = readAt == null ? '' : ' · ${readAt.hour.toString().padLeft(2, '0')}:${readAt.minute.toString().padLeft(2, '0')}:${readAt.second.toString().padLeft(2, '0')} 读取';
    final scanning = widget.scanStatus == WifiFormScanStatus.scanning;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
      children: [
        Text('填写并确认 Wi-Fi', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        if (widget.onRefreshPhoneWifi != null) ...[
          const Text('读取手机连接的 Wi-Fi 名称需要定位权限；拒绝后仍可手动填写或让盒子搜索。', style: TextStyle(color: AppColors.inkMuted)),
          if (phone != null || widget.initialHint != null)
            Text(
              phone?.isReadable == true ? '手机当前连接：${phone!.ssid}$readTime' : (phone?.hint ?? widget.initialHint!),
              key: const ValueKey('wifi-prefill-hint'),
            ),
          if (phone?.isReadable == true) const Text('来源：手机 Wi-Fi 读取；请确认下面表单中的目标。'),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                key: const ValueKey('wifi-refresh-phone'),
                onPressed: widget.readingPhoneWifi ? null : widget.onRefreshPhoneWifi,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(widget.readingPhoneWifi ? '正在读取名称…' : '刷新手机 Wi-Fi 名称'),
              ),
              if (phone?.isReadable == true && widget.manualSupported && _networkKind != StaNetworkKind.thisPhoneHotspot && (_ssidController.text != phone!.ssid || _selected != null))
                TextButton(onPressed: _usePhoneName, child: const Text('使用此名称')),
            ],
          ),
        ] else if (widget.initialHint != null)
          Text(widget.initialHint!, key: const ValueKey('wifi-prefill-hint')),
        if (widget.savedNetwork?.saved == true) ...[
          Text('盒子已保存配置：${widget.savedNetwork!.ssid ?? '未返回名称'}（盒子记录，不代表手机当前连接）', key: const ValueKey('wifi-box-saved')),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_networkKind == StaNetworkKind.thisPhoneHotspot) ...[
          const Text('本机热点：请先在手机系统热点设置中开启热点，并填写其中的名称和密码。手机连接的 Wi-Fi 名称不作为热点名称。', key: ValueKey('wifi-hotspot-hint')),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextField(
          key: const ValueKey('wifi-ssid'),
          controller: _ssidController,
          readOnly: !widget.manualSupported,
          decoration: InputDecoration(labelText: 'Wi-Fi 名称', errorText: _ssidError, helperText: _nameEvidence == null ? null : '名称来源：手机 Wi-Fi · ${_formatReadTime(_nameEvidence!.readAt)} 读取'),
          onChanged: (_) => setState(() {
            _ssidEdited = true;
            _nameEvidence = null;
            _selected = null;
            _clearPassword();
            _ssidError = null;
            _editRevision++;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<WifiSecurity>(
          key: ValueKey('wifi-security-${_security.name}'),
          initialValue: _security,
          decoration: const InputDecoration(labelText: '安全类型'),
          items: WifiSecurity.values.map((value) => DropdownMenuItem(value: value, child: Text(wifiSecurityLabel(value)))).toList(),
          onChanged: !widget.manualSupported
              ? null
              : (value) => setState(() {
                  if (value == null || value == _security) return;
                  _security = value;
                  _selected = null;
                  _clearPassword();
                  _editRevision++;
                }),
        ),
        if (_selected != null) Text('已选择：${_selected!.bssid} · ${_selected!.rssiDbm} dBm', key: const ValueKey('wifi-selected-source')),
        if (_security != WifiSecurity.open) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('wifi-password'),
            controller: _passwordController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(labelText: 'Wi-Fi 密码', errorText: _passwordError),
            onChanged: (_) => _editRevision++,
          ),
        ] else
          const SizedBox(key: ValueKey('wifi-password')),
        if (widget.manualSupported && _selected == null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('隐藏网络'),
            value: _hidden,
            onChanged: (value) => setState(() {
              _hidden = value;
              _editRevision++;
            }),
          ),
        DropdownButtonFormField<StaNetworkKind>(
          key: const ValueKey('wifi-network-kind'),
          initialValue: _networkKind,
          decoration: const InputDecoration(labelText: '网络类型'),
          items: StaNetworkKind.values.map((value) => DropdownMenuItem(value: value, child: Text(_networkKindLabel(value)))).toList(),
          onChanged: (value) {
            if (value != null) _changeKind(value);
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        BirdButton(
          label: '连接此 Wi-Fi',
          onPressed: scanning || (!widget.manualSupported && _selected == null) ? null : _submit,
          icon: const Icon(Icons.wifi_rounded),
        ),
        if (widget.onScan != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const BirdSectionTitle(text: '盒子搜索附近 Wi-Fi'),
          if (scanning) ...[
            const LinearProgressIndicator(),
            const Text('正在搜索 Wi-Fi，已填写的内容会保留。'),
            TextButton(onPressed: widget.onCancelScan, child: Text(widget.onCancelScan == null ? '正在取消搜索…' : '取消搜索')),
          ] else ...[
            if (widget.scanStatus == WifiFormScanStatus.failed) const Text('搜索失败，已填写的内容已保留，可重试或手动连接。'),
            if (widget.scanStatus == WifiFormScanStatus.cancelled) const Text('已取消搜索，已填写的内容已保留。'),
            if (widget.scanStatus == WifiFormScanStatus.complete && widget.networks.isEmpty) const Text('未发现附近 Wi-Fi，可重新搜索或手动填写隐藏网络。'),
            BirdButton(label: widget.scanStatus == WifiFormScanStatus.idle ? '搜索附近 Wi-Fi' : '重新搜索', onPressed: widget.onScan, variant: BirdButtonVariant.outlined),
          ],
          for (final network in widget.networks) ...[
            const SizedBox(height: AppSpacing.sm),
            BirdCard(
              key: ValueKey('wifi-result-${network.bssid}'),
              onTap: network.unsupported || scanning ? null : () => setState(() => _chooseNetwork(network)),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(network.unsupported ? Icons.block_rounded : Icons.wifi_rounded),
                title: Text(network.ssid.isEmpty ? '隐藏网络' : network.ssid),
                subtitle: Text('${network.unsupported ? '当前不支持此网络的安全类型' : wifiSecurityLabel(network.security)} · ${network.bssid}'),
                trailing: Text('${network.rssiDbm} dBm'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

String wifiSecurityLabel(WifiSecurity security) => switch (security) {
  WifiSecurity.open => '开放网络',
  WifiSecurity.wpa2Personal => 'WPA2',
  WifiSecurity.wpa3Personal => 'WPA3',
  WifiSecurity.wpa2Wpa3Transition => 'WPA2/WPA3',
};

String _formatReadTime(DateTime? value) {
  final time = value?.toLocal();
  return time == null ? '本次' : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
}

String _networkKindLabel(StaNetworkKind kind) => switch (kind) {
  StaNetworkKind.router => '路由器',
  StaNetworkKind.thisPhoneHotspot => '本机热点',
  StaNetworkKind.otherPhoneHotspot => '其他手机热点',
  StaNetworkKind.unknown => '其他网络',
};
