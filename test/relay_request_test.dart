import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundhound/protocol/relay_client.dart';

void main() {
  test('member removal carries a reason to the relay', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<(String, String, Map<String, dynamic>)>();
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      received.complete((request.method, request.uri.path, body));
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });
    try {
      final url = 'http://127.0.0.1:${server.port}';
      final identity = RelayIdentity(url, 'ABCDE', 'self', 'Master',
        'example-token', true);
      await RelayClient.forIdentity(identity).remove(identity, 'other',
        reason: 'no-shared-sky');
      final (method, path, payload) = await received.future;
      expect(method, 'DELETE');
      expect(path, '/v1/groups/ABCDE/members/other');
      expect(payload, {'reason': 'no-shared-sky'});
    } finally {
      await server.close(force: true);
    }
  });

  test('group creation sends a length-delimited JSON object', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<(int, List<int>, String)>();
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(<int>[],
        (all, chunk) => all..addAll(chunk));
      received.complete((request.contentLength, bytes, request.uri.path));
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });
    try {
      final relay = RelayClient('http://127.0.0.1:${server.port}');
      final reply = await relay.request('POST', '/v1/groups',
        {'tag': 'Master', 'demo': false});
      final (length, bytes, path) = await received.future;
      expect(reply['ok'], isTrue);
      expect(path, '/v1/groups');
      expect(length, bytes.length);
      expect(jsonDecode(utf8.decode(bytes)),
        {'tag': 'Master', 'demo': false});
    } finally {
      await server.close(force: true);
    }
  });
}
