// mobile_app/test/services_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pae_mobile/src/services/api_exception.dart';

void main() {
  group('ApiException', () {
    test('Format exception without status code', () {
      const exc = ApiException('Network timeout');
      expect(exc.toString(), 'Network timeout');
    });

    test('Format exception with status code', () {
      const exc = ApiException('Unauthorized', statusCode: 401);
      expect(exc.toString(), '[401] Unauthorized');
    });

    test('ApiException message property', () {
      const exc = ApiException('Error', statusCode: 500);
      expect(exc.message, 'Error');
      expect(exc.statusCode, 500);
    });
  });
}
