import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PairingCodeForm extends StatefulWidget {
  const PairingCodeForm({
    super.key,
    required this.deviceName,
    this.codeMode = PairingCodeMode.sessionRandom,
    this.codeLength = 4,
    this.displayAvailable = true,
    required this.onSubmit,
    required this.onCancel,
    this.onCopyDiagnostic,
  });

  final String deviceName;
  final PairingCodeMode codeMode;
  final int codeLength;
  final bool displayAvailable;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final VoidCallback? onCopyDiagnostic;

  @override
  State<PairingCodeForm> createState() => _PairingCodeFormState();
}

class _PairingCodeFormState extends State<PairingCodeForm> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 配对页常在 BLE 阶段切换的同一帧挂载，autofocus 的申请可能赶在 IME 就绪
    // 之前（真机键盘概率性不弹）；首帧落定后补一次焦点请求，已聚焦时是 no-op。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
        _instruction,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: AppSpacing.lg),
      TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        // 配对码是纯数字（RC4 协议与两段模拟码均为数字）。不用
        // visiblePassword：MIUI 的 SecurityInputMethodSwitcher 会在密码类
        // 输入框上切换到安全输入法，切换偶发超时（PHASE_SERVER_WAIT_IME
        // STATUS_TIMEOUT），键盘概率性弹不出来；数字键盘不触发该切换。
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: widget.codeLength,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: '配对码',
          hintText: '${widget.codeLength} 位配对码',
          counterText: '',
          prefixIcon: const Icon(Icons.password_rounded),
        ),
        onSubmitted: _submit,
      ),
      const SizedBox(height: AppSpacing.lg),
      BirdButton(
        label: '安全配对并连接',
        onPressed: () => _submit(_controller.text),
        icon: const Icon(Icons.lock_open_rounded),
      ),
      if (widget.onCopyDiagnostic != null) ...[
        const SizedBox(height: AppSpacing.sm),
        BirdButton(
          key: const Key('ble-copy-pairing-diagnostic-json'),
          label: '复制本次配对诊断',
          onPressed: widget.onCopyDiagnostic,
          icon: const Icon(Icons.copy_all_outlined),
          variant: BirdButtonVariant.outlined,
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      TextButton(onPressed: widget.onCancel, child: const Text('取消')),
    ],
  );

  void _submit(String value) {
    final code = value.trim();
    if (code.length != widget.codeLength) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入 ${widget.codeLength} 位配对码。')));
      return;
    }
    widget.onSubmit(code);
  }

  String get _instruction {
    if (widget.displayAvailable) {
      return '请输入盒子屏幕上显示的 ${widget.codeLength} 位配对码。';
    }
    return widget.codeMode == PairingCodeMode.fixedDev ? '请查看盒子提示后输入 ${widget.codeLength} 位配对码。' : '请确认盒子已显示配对码后输入 ${widget.codeLength} 位配对码。';
  }
}
