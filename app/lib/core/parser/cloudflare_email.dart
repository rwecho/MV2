import 'dart:convert';

import 'package:html/dom.dart';

/// Restores the email markup that Cloudflare normally decodes in JavaScript.
/// Also applied at render time so previously cached HTML is displayed correctly.
void decodeCloudflareEmails(Node root) {
  for (final child in root.nodes.toList(growable: false)) {
    decodeCloudflareEmails(child);
  }
  if (root is! Element) return;

  final href = root.attributes['href'];
  final uri = href == null ? null : Uri.tryParse(href);
  final protectedLink = uri?.path == '/cdn-cgi/l/email-protection';
  final encoded =
      root.attributes['data-cfemail'] ?? (protectedLink ? uri?.fragment : null);
  if (encoded == null) return;
  final email = _decodeEmail(encoded);
  if (email == null) return;

  root.text = email;
  root.attributes.remove('data-cfemail');
  root.classes.remove('__cf_email__');
  if (root.localName == 'a') {
    root.attributes['href'] = Uri(scheme: 'mailto', path: email).toString();
  } else if (root.parent?.localName == 'a') {
    final parent = root.parent!;
    final parentUri = Uri.tryParse(parent.attributes['href'] ?? '');
    if (parentUri?.path == '/cdn-cgi/l/email-protection') {
      parent.attributes['href'] = Uri(scheme: 'mailto', path: email).toString();
    }
  }
}

String? _decodeEmail(String encoded) {
  if (encoded.length < 4 ||
      encoded.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(encoded)) {
    return null;
  }
  final key = int.parse(encoded.substring(0, 2), radix: 16);
  try {
    final email = utf8.decode([
      for (var i = 2; i < encoded.length; i += 2)
        int.parse(encoded.substring(i, i + 2), radix: 16) ^ key,
    ]);
    if (!RegExp(r'^[^\s@\x00-\x1f\x7f]+@[^\s@\x00-\x1f\x7f]+$')
        .hasMatch(email)) {
      return null;
    }
    return email;
  } on FormatException {
    return null;
  }
}
