// Copyright 2018 Dart Mockito authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

/// Every method on this class has a nullable return type and nullable parameter
/// types. This allows each method to be verified without manual overriding or
/// code-generation.
class _RealClass {
  String? methodWithoutArgs() => 'Real';
  String? methodWithNormalArgs(int? x) => 'Real';
  String? methodWithListArgs(List<int>? x) => 'Real';
  String? methodWithOptionalArg([int? x]) => 'Real';
  String? methodWithPositionalArgs(int? x, [int? y]) => 'Real';
  String? methodWithNamedArgs(int x, {int? y}) => 'Real';
  String? methodWithOnlyNamedArgs({int? y = 0, int? z}) => 'Real';
  String? get getter => 'Real';
  set setter(String arg) {
    throw StateError('I must be mocked');
  }

  String? methodWithLongArgs(LongToString? a, LongToString? b,
          {LongToString? c, LongToString? d}) =>
      'Real';
}

class LongToString {
  final List aList;
  final Map aMap;
  final String aString;

  LongToString(this.aList, this.aMap, this.aString);

  @override
  String toString() => 'LongToString<\n'
      '    aList: $aList\n'
      '    aMap: $aMap\n'
      '    aString: $aString\n'
      '>';
}

class _MockedClass extends Mock implements _RealClass {}

void expectFail(Pattern expectedMessage, void Function() expectedToFail) {
  try {
    expectedToFail();
    fail('It was expected to fail!');
  } on TestFailure catch (e) {
    expect(e.message,
        expectedMessage is String ? expectedMessage : contains(expectedMessage),
        reason: 'Failed but with unexpected message');
  }
}

const noMatchingCallsFooter = '(If you called `verify(...).called(0);`, '
    'please instead use `verifyNever(...);`.)';

void main() {
  late _MockedClass mock;

  setUp(() {
    mock = _MockedClass();
  });

  tearDown(() {
    // In some of the tests that expect an Error to be thrown, Mockito's
    // global state can become invalid. Reset it.
    resetMockitoState();
  });

  group('verify', () {
    test('should verify method without args', () {
      mock.methodWithoutArgs();
      verify(mock.methodWithoutArgs());
    });

    test('should verify method with normal args', () {
      mock.methodWithNormalArgs(42);
      verify(mock.methodWithNormalArgs(42));
    });

    test('should mock method with positional args', () {
      mock.methodWithPositionalArgs(42, 17);
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithPositionalArgs(42, 17)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithPositionalArgs(42));
      });
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithPositionalArgs(42, 17)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithPositionalArgs(42, 18));
      });
      verify(mock.methodWithPositionalArgs(42, 17));
    });

    test('should mock method with named args', () {
      mock.methodWithNamedArgs(42, y: 17);
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithNamedArgs(42, {y: 17})\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithNamedArgs(42));
      });
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithNamedArgs(42, {y: 17})\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithNamedArgs(42, y: 18));
      });
      verify(mock.methodWithNamedArgs(42, y: 17));
    });

    test('should mock method with list args', () {
      mock.methodWithListArgs([42]);
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithListArgs([42])\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithListArgs([43]));
      });
      verify(mock.methodWithListArgs([42]));
    });

    test('should mock method with argument matcher', () {
      mock.methodWithNormalArgs(100);
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithNormalArgs(100)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithNormalArgs(argThat(greaterThan(100))));
      });
      verify(mock.methodWithNormalArgs(argThat(greaterThanOrEqualTo(100))));
    });

    test('should mock method with mix of argument matchers and real things',
        () {
      mock.methodWithPositionalArgs(100, 17);
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithPositionalArgs(100, 17)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithPositionalArgs(
            argThat(greaterThanOrEqualTo(100)), 18));
      });
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithPositionalArgs(100, 17)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithPositionalArgs(argThat(greaterThan(100)), 17));
      });
      verify(mock.methodWithPositionalArgs(
          argThat(greaterThanOrEqualTo(100)), 17));
    });

    test('should mock getter', () {
      mock.getter;
      verify(mock.getter);
    });

    test('should mock setter', () {
      mock.setter = 'A';
      final expectedMessage = RegExp.escape('No matching calls. '
          'All calls: _MockedClass.setter==\'A\'\n$noMatchingCallsFooter');
      // RegExp needed because of https://github.com/dart-lang/sdk/issues/33565
      var expectedPattern = RegExp(expectedMessage.replaceFirst('==', '=?='));

      expectFail(expectedPattern, () => verify(mock.setter = 'B'));
      verify(mock.setter = 'A');
    });

    test('should throw meaningful errors when verification is interrupted', () {
      int badHelper() => throw 'boo';

      try {
        verify(mock.methodWithNamedArgs(42, y: badHelper()));
      } catch (_) {}
      // At this point, verification was interrupted, so
      // `_verificationInProgress` is still `true`. Calling mock methods below
      // adds items to `_verifyCalls`.
      mock.methodWithNamedArgs(42, y: 17);
      mock.methodWithNamedArgs(42, y: 17);
      try {
        verify(mock.methodWithNamedArgs(42, y: 17));
        fail('verify call was expected to throw!');
      } catch (exception) {
        expect(
            exception,
            isA<StateError>().having(
                (exception) => exception.message,
                'message',
                contains('Verification appears to be in progress. '
                    '2 verify calls have been stored.')));
      }
    });

    test('should fail when called with non-mock-call parameter', () {
      expectFail('Used on a non-mockito object', () {
        verify(['a string is not a mock call']);
      });
    });
  });

  group('verify should fail when no matching call is found', () {
    test('and there are no unmatched calls', () {
      expectFail(
          'No matching calls (actually, no calls at all).\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithNormalArgs(43));
      });
    });

    test('and there is one unmatched call', () {
      mock.methodWithNormalArgs(42);
      expectFail(
          'No matching calls. All calls: _MockedClass.methodWithNormalArgs(42)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithNormalArgs(43));
      });
    });

    test('and there is one unmatched call without args', () {
      mock.methodWithOptionalArg();
      expectFail(
          'No matching calls. All calls: _MockedClass.methodWithOptionalArg(null)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithOptionalArg(43));
      });
    });

    test('and there are multiple unmatched calls', () {
      mock.methodWithNormalArgs(41);
      mock.methodWithNormalArgs(42);
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithNormalArgs(41), '
          '_MockedClass.methodWithNormalArgs(42)\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithNormalArgs(43));
      });
    });

    test('and unmatched calls have only named args', () {
      mock.methodWithOnlyNamedArgs(y: 1);
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithOnlyNamedArgs({y: 1, z: null})\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithOnlyNamedArgs());
      });
    });
  });

  group('verify qualifies', () {
    group('unqualified as at least one', () {
      test('zero fails', () {
        expectFail(
            'No matching calls (actually, no calls at all).\n'
            '$noMatchingCallsFooter', () {
          verify(mock.methodWithoutArgs());
        });
      });

      test('one passes', () {
        mock.methodWithoutArgs();
        verify(mock.methodWithoutArgs());
      });

      test('more than one passes', () {
        mock.methodWithoutArgs();
        mock.methodWithoutArgs();
        verify(mock.methodWithoutArgs());
      });
    });

    group('expecting one call', () {
      test('zero actual calls fails', () {
        expectFail(
            'No matching calls (actually, no calls at all).\n'
            '$noMatchingCallsFooter', () {
          verify(mock.methodWithoutArgs()).called(1);
        });
      });

      test('one actual call passes', () {
        mock.methodWithoutArgs();
        verify(mock.methodWithoutArgs()).called(1);
      });

      test('more than one actual call fails', () {
        mock.methodWithoutArgs();
        mock.methodWithoutArgs();
        expectFail('Expected: <1>\n  Actual: <2>\nUnexpected number of calls\n',
            () {
          verify(mock.methodWithoutArgs()).called(1);
        });
      });
    });

    group('expecting more than two calls', () {
      test('zero actual calls fails', () {
        expectFail(
            'No matching calls (actually, no calls at all).\n'
            '$noMatchingCallsFooter', () {
          verify(mock.methodWithoutArgs()).called(greaterThan(2));
        });
      });

      test('one actual call fails', () {
        mock.methodWithoutArgs();
        expectFail(
            'Expected: a value greater than <2>\n'
            '  Actual: <1>\n'
            '   Which: is not a value greater than <2>\n'
            'Unexpected number of calls\n', () {
          verify(mock.methodWithoutArgs()).called(greaterThan(2));
        });
      });

      test('three actual calls passes', () {
        mock.methodWithoutArgs();
        mock.methodWithoutArgs();
        mock.methodWithoutArgs();
        verify(mock.methodWithoutArgs()).called(greaterThan(2));
      });
    });

    group('expecting zero calls', () {
      test('zero actual calls passes', () {
        expectFail(
            'No matching calls (actually, no calls at all).\n'
            '$noMatchingCallsFooter', () {
          verify(mock.methodWithoutArgs()).called(0);
        });
      });

      test('one actual call fails', () {
        mock.methodWithoutArgs();
        expectFail(
            'Expected: <0>\n'
            '  Actual: <1>\n'
            'Unexpected number of calls\n', () {
          verify(mock.methodWithoutArgs()).called(0);
        });
      });
    });

    group('verifyNever', () {
      test('zero passes', () {
        verifyNever(mock.methodWithoutArgs());
      });

      test('one fails', () {
        // Add one verified method that should not appear in message.
        mock.methodWithNormalArgs(1);
        verify(mock.methodWithNormalArgs(1)).called(1);

        mock.methodWithoutArgs();
        expectFail('Unexpected calls: _MockedClass.methodWithoutArgs()', () {
          verifyNever(mock.methodWithoutArgs());
        });
      });
    });

    group('does not count already verified again', () {
      test('fail case', () {
        mock.methodWithoutArgs();
        verify(mock.methodWithoutArgs());
        expectFail(
            'No matching calls. '
            'All calls: [VERIFIED] _MockedClass.methodWithoutArgs()\n'
            '$noMatchingCallsFooter', () {
          verify(mock.methodWithoutArgs());
        });
      });

      test('pass case', () {
        mock.methodWithoutArgs();
        verify(mock.methodWithoutArgs());
        mock.methodWithoutArgs();
        verify(mock.methodWithoutArgs());
      });
    });
  });

  group('verifyZeroInteractions', () {
    test('never touched pass', () {
      verifyZeroInteractions(mock);
    });

    test('any touch fails', () {
      mock.methodWithoutArgs();
      expectFail(
          'No interaction expected, but following found: '
          '_MockedClass.methodWithoutArgs()', () {
        verifyZeroInteractions(mock);
      });
    });

    test('verified call fails', () {
      mock.methodWithoutArgs();
      verify(mock.methodWithoutArgs());
      expectFail(
          'No interaction expected, but following found: '
          '[VERIFIED] _MockedClass.methodWithoutArgs()', () {
        verifyZeroInteractions(mock);
      });
    });
  });

  group('verifyNoMoreInteractions', () {
    test('never touched pass', () {
      verifyNoMoreInteractions(mock);
    });

    test('any unverified touch fails', () {
      mock.methodWithoutArgs();
      expectFail(
          'No more calls expected, but following found: '
          '_MockedClass.methodWithoutArgs()', () {
        verifyNoMoreInteractions(mock);
      });
    });

    test('verified touch passes', () {
      mock.methodWithoutArgs();
      verify(mock.methodWithoutArgs());
      verifyNoMoreInteractions(mock);
    });

    test('throws if given a real object', () {
      expect(() => verifyNoMoreInteractions(_RealClass()), throwsArgumentError);
    });
  });

  group('verifyInOrder', () {
    test('right order passes', () {
      mock.methodWithoutArgs();
      mock.getter;
      verifyInOrder([mock.methodWithoutArgs(), mock.getter]);
    });

    test('wrong order fails', () {
      mock.methodWithoutArgs();
      mock.getter;
      expectFail(
          'Matching call #1 not found. All calls: '
          '_MockedClass.methodWithoutArgs(), _MockedClass.getter', () {
        verifyInOrder([mock.getter, mock.methodWithoutArgs()]);
      });
    });

    test('should fail when given non-mock-call parameters', () {
      expectFail(
          RegExp("'verifyInOrder' called with non-mockito stub calls; List "
              'contains 3 elements, but 2 stub calls were stored'), () {
        verifyInOrder([mock.getter, mock.methodWithoutArgs, mock.getter]);
      });
    });

    test('should fail when parameters do not map to List elements', () {
      expectFail(
          RegExp("'verifyInOrder' called with non-mockito stub calls; List "
              'contains 1 elements, but 2 stub calls were stored'), () {
        verifyInOrder([
          [mock.getter, mock.getter]
        ]);
      });
    });

    test('verify been used as an argument fails', () {
      mock.methodWithoutArgs();
      mock.getter;
      expectFail(
          'There is already a verification in progress, '
          'check if it was not called with a verify argument(s)', () {
        verifyInOrder([
          verify(mock.getter),
          verify(mock.methodWithoutArgs()),
        ]);
      });
    });

    test('incomplete fails', () {
      mock.methodWithoutArgs();
      expectFail(
          'Matching call #1 not found. All calls: '
          '_MockedClass.methodWithoutArgs()', () {
        verifyInOrder([mock.methodWithoutArgs(), mock.getter]);
      });
    });

    test('methods can be called again and again', () {
      mock.methodWithoutArgs();
      mock.getter;
      mock.methodWithoutArgs();
      verifyInOrder(
          [mock.methodWithoutArgs(), mock.getter, mock.methodWithoutArgs()]);
    });

    test('can return captures from capturing argument matchers', () {
      mock.methodWithNormalArgs(1);
      mock.methodWithoutArgs();
      mock.methodWithNormalArgs(2);
      var captured = verifyInOrder([
        mock.methodWithNormalArgs(captureAny),
        mock.methodWithoutArgs(),
        mock.methodWithNormalArgs(captureAny)
      ]).captured;
      expect(captured, hasLength(3));
      expect(captured[0], equals([1]));
      expect(captured[1], equals([]));
      expect(captured[2], equals([2]));
    });

    test('methods can be called again and again - fail case', () {
      mock.methodWithoutArgs();
      mock.methodWithoutArgs();
      mock.getter;
      expectFail(
          'Matching call #2 not found. All calls: '
          '_MockedClass.methodWithoutArgs(), _MockedClass.methodWithoutArgs(), '
          '_MockedClass.getter', () {
        verifyInOrder(
            [mock.methodWithoutArgs(), mock.getter, mock.methodWithoutArgs()]);
      });
    });
  });

  group('multiline toStrings on objects', () {
    test(
        '"No matching calls" message visibly separates unmatched calls, '
        'if an arg\'s string representations is multiline', () {
      mock.methodWithLongArgs(LongToString([1, 2], {1: 'a', 2: 'b'}, 'c'),
          LongToString([4, 5], {3: 'd', 4: 'e'}, 'f'));
      mock.methodWithLongArgs(null, null,
          c: LongToString([5, 6], {5: 'g', 6: 'h'}, 'i'),
          d: LongToString([7, 8], {7: 'j', 8: 'k'}, 'l'));
      expectFail(
          'No matching calls. All calls: '
          '_MockedClass.methodWithLongArgs(\n'
          '    LongToString<\n'
          '        aList: [1, 2]\n'
          '        aMap: {1: a, 2: b}\n'
          '        aString: c\n'
          '    >,\n'
          '    LongToString<\n'
          '        aList: [4, 5]\n'
          '        aMap: {3: d, 4: e}\n'
          '        aString: f\n'
          '    >, {c: null, d: null}),\n'
          '_MockedClass.methodWithLongArgs(null, null, {\n'
          '    c: LongToString<\n'
          '        aList: [5, 6]\n'
          '        aMap: {5: g, 6: h}\n'
          '        aString: i\n'
          '    >,\n'
          '    d: LongToString<\n'
          '        aList: [7, 8]\n'
          '        aMap: {7: j, 8: k}\n'
          '        aString: l\n'
          '    >})\n'
          '$noMatchingCallsFooter', () {
        verify(mock.methodWithNormalArgs(43));
      });
    });
  });
}
