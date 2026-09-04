import 'dart:async';

import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:aves/bird_companion/features/connection/presentation/b7_simulated_provisioning_repository.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/material.dart';

/// A runnable B7 simulated flow for demonstrations and acceptance recordings.
/// The page uses the production connection presentation and a deterministic
/// repository, keeping simulated dependencies outside the production graph.
class B7SimulatedDemoPage extends StatefulWidget {
  const B7SimulatedDemoPage({
    super.key,
    this.repository,
    this.onProvisioningCompleted,
    this.titlePrefix,
  });

  final B7SimulatedProvisioningRepository? repository;
  final ProvisioningCompletionHandler? onProvisioningCompleted;
  final String? titlePrefix;

  @override
  State<B7SimulatedDemoPage> createState() => _B7SimulatedDemoPageState();
}

class _B7SimulatedDemoPageState extends State<B7SimulatedDemoPage> {
  late final B7SimulatedProvisioningRepository _repository = widget.repository ?? B7SimulatedProvisioningRepository();

  @override
  void dispose() {
    if (widget.repository == null) unawaited(_repository.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConnectionPage(
    provisioningRepository: _repository,
    onProvisioningCompleted: widget.onProvisioningCompleted,
    titlePrefix: widget.titlePrefix,
  );
}
