import 'package:flutter/material.dart';

import 'models.dart';

/// Maps a V2EX node slug to the icon/colour the MV2 design system uses.
///
/// V2EX gives us only `name` + `/go/{key}`; the visual identity is a product
/// decision, so the mapping lives with the model rather than in a page.
abstract final class NodeVisuals {
  static const Map<String, IconData> _icons = <String, IconData>{
    'programmer': Icons.code,
    'create': Icons.lightbulb_outline,
    'ai': Icons.auto_awesome,
    'apple': Icons.apple,
    'qna': Icons.help_outline,
    'idev': Icons.rocket_launch_outlined,
    'jobs': Icons.work_outline,
    'share': Icons.share_outlined,
    'deals': Icons.local_offer_outlined,
    'city': Icons.location_city_outlined,
    'security': Icons.shield_outlined,
    'dotnet': Icons.terminal,
    'remote': Icons.laptop_mac,
    'devtools': Icons.build_outlined,
    'r2': Icons.cloud_outlined,
  };

  /// Nodes rendered as a soft tint with a coloured glyph instead of a solid
  /// tile (matches `designs/04-nodes-explore.png`).
  static const Set<String> _softNodes = <String>{'ai'};

  static IconData iconFor(String key) => _icons[key] ?? Icons.tag;

  static NodeIconStyle styleFor(String key) =>
      _softNodes.contains(key) ? NodeIconStyle.soft : NodeIconStyle.solid;

  /// Builds a [V2Node] from a node slug + display name. [nodeId] carries the
  /// numeric V2EX id when the payload exposes one (`/api/nodes/all.json`).
  static V2Node node({
    required String key,
    required String name,
    int? topicCount,
    String? description,
    List<String> tags = const <String>[],
    int? nodeId,
  }) {
    return V2Node(
      key: key,
      name: name,
      icon: iconFor(key),
      topicCount: topicCount,
      description: description,
      tags: tags,
      iconStyle: styleFor(key),
      nodeId: nodeId,
    );
  }
}
