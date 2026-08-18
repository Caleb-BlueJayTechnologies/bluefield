import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// A persistent, unmissable indicator of which Firebase project the
/// admin panel is currently talking to — flagged "Critical" in the
/// admin roadmap because an admin action landing in the wrong
/// environment (e.g. suspending a company in prod while meaning to
/// test in dev) is exactly the kind of mistake this exists to prevent.
///
/// Reads Firebase.app().options.projectId at runtime rather than
/// hardcoding project names, so it stays accurate no matter how many
/// environments end up configured or what they're actually named.
class EnvironmentIndicator extends StatelessWidget {
  const EnvironmentIndicator({super.key});

  ({String label, Color color}) _classify(String projectId) {
    final lower = projectId.toLowerCase();
    if (lower.contains('prod')) {
      return (label: 'PRODUCTION', color: Colors.red.shade700);
    }
    if (lower.contains('staging') || lower.contains('stage')) {
      return (label: 'STAGING', color: Colors.orange.shade700);
    }
    if (lower.contains('dev') || lower.contains('test')) {
      return (label: 'DEVELOPMENT', color: Colors.blue.shade700);
    }
    // Unrecognized naming — still show something actionable rather
    // than silently assuming it's safe.
    return (label: 'UNKNOWN ENV', color: Colors.grey.shade700);
  }

  @override
  Widget build(BuildContext context) {
    String projectId;
    try {
      projectId = Firebase.app().options.projectId;
    } catch (_) {
      projectId = 'unavailable';
    }

    final classification = _classify(projectId);

    return Container(
      width: double.infinity,
      color: classification.color,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${classification.label} — $projectId',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
