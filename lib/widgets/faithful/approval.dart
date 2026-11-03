// showApprovalDialog — the #11 ApprovalCard as a modal decision surface
// (replaces the stock AlertDialog from 1.4.0). Same contract as before:
// resolves true on approve, false on reject/dismiss.
import 'package:flutter/material.dart';
import 'controls_meta.dart';

Future<bool> showApprovalDialog(
  BuildContext context, {
  required String title,
  required String itemName,
  required double sizeGb,
  String confirmLabel = 'Download',
  String? note,
}) async {
  final body = StringBuffer()
    ..write(itemName)
    ..write('\n\n${sizeGb.toStringAsFixed(1)} GB');
  if (note != null) {
    body.write('\n$note');
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ApprovalCard(
        title: title,
        body: body.toString(),
        approveLabel: confirmLabel,
        rejectLabel: 'Cancel',
        onApprove: () => Navigator.of(ctx).pop(true),
        onReject: () => Navigator.of(ctx).pop(false),
      ),
    ),
  );
  return result ?? false;
}
