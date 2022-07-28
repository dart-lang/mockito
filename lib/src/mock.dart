// Copyright 2016 Dart Mockito authors
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

// The API in this file includes functions that return `void`, but are intended
// to be passed as arguments to method stubs, so they must be declared to return
// `Null` in order to not trigger `use_of_void_result` warnings in user code.
// ignore_for_file: prefer_void_to_null

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:mockito/src/call_pair.dart';
import 'package:mockito/src/invocation_matcher.dart';
// ignore: deprecated_member_use
import 'package:test_api/fake.dart';
// ignore: deprecated_member_use
import 'package:test_api/test_api.dart';

/// Whether a [when] call is "in progress."
///
/// Since [when] is a getter, this is `true` immediately after [when] returns,
/// `false` immediately after the closure which [when] returns has returned, and
/// `false` otherwise. For example:
///
/// ```none
/// ,--- (1) Before [when] is called, [_whenInProgress] is `false`.
/// |  ,--- (2) The [when] getter sets [_whenInProgress] to `true`, so that it
/// |  |        is true immediately after [when] returns.
/// |  | ,--- (3) The argument given to [when]'s return closure is computed
/// |  | |        before entering the closure, so [_whenInProgress] is still
/// |  | |        `true`.
/// |  | |         ,--- (4) The closure resets [_whenInProgress] to `false`.
/// v  v v         v
/// when(foo.bar()).thenReturn(7);
/// ```
bool _whenInProgress = false;

/// Whether an [untilCalled] call is "in progress."
///
/// This follows similar logic to [_whenInProgress]; see its comment.
bool _untilCalledInProgress = false;

/// Whether a [verify], [verifyNever], or [verifyInOrder] call is "in progress."
///
/// This follows similar logic to [_whenInProgress]; see its comment.
bool _verificationInProgress = false;

_WhenCall? _whenCall;
_UntilCall? _untilCall;
final List<_VerifyCall> _verifyCalls = <_VerifyCall>[];
final _TimeStampProvider _timer = _TimeStampProvider();
final List<dynamic> _capturedArgs = [];
final List<ArgMatcher> _storedArgs = <ArgMatcher>[];
final Map<String, ArgMatcher> _storedNamedArgs = <String, ArgMatcher>{};

@Deprecated(
    'This function is not a supported function, and may be deleted as early as '
    'Mockito 5.0.0')
void setDefaultResponse(
    Mock mock, CallPair<dynamic> Function() defaultResponse) {
  mock._defaultResponse = defaultResponse;
}

/// Opt-into [Mock] throwing [NoSuchMethodError] for unimplemented methods.
///
/// The default behavior when not using this is to always return `null`.
void throwOnMissingStub(
  Mock mock, {
  void Function(Invocation)? exceptionBuilder,
}) {
  exceptionBuilder ??= mock._noSuchMethod;
  mock._defaultResponse =
      () => CallPair<dynamic>.allInvocations(exceptionBuilder!);
}

/// Extend or mixin this class to mark the implementation as a [Mock].
///
/// A mocked class implements all fields and methods with a default
/// implementation that does not throw a [NoSuchMethodError], and may be further
/// customized at runtime to define how it may behave using [when].
///
/// __Example use__:
///
///     // Real class.
///     class Cat {
///       String getSound(String suffix) => 'Meow$suffix';
///     }
///
///     // Mock class.
///     class MockCat extends Mock implements Cat {}
///
///     void main() {
///       // Create a new mocked Cat at runtime.
///       var cat = new MockCat();
///
///       // When 'getSound' is called, return 'Woof'
///       when(cat.getSound(any)).thenReturn('Woof');
///
///       // Try making a Cat sound...
///       print(cat.getSound('foo')); // Prints 'Woof'
///     }
///
/// A class which `extends Mock` should not have any directly implemented
/// overridden fields or methods. These fields would not be usable as a [Mock]
/// with [verify] or [when]. To implement a subset of an interface manually use
/// [Fake] instead.
///
/// **WARNING**: [Mock] uses
/// [noSuchMethod](http://bit.ly/dart-emulating-functions)
/// , which is a _form_ of runtime reflection, and causes sub-standard code to
/// be generated. As such, [Mock] should strictly _not_ be used in any
/// production code, especially if used within the context of Dart for Web
/// (dart2js, DDC) and Dart for Mobile (Flutter).
class Mock {
  static Null _answerNull(_) => null;

  static const _nullResponse = CallPair<Null>.allInvocations(_answerNull);

  final StreamController<Invocation> _invocationStreamController =
      StreamController.broadcast();
  final _realCalls = <RealCall>[];
  final _responses = <CallPair<dynamic>>[];

  String? _givenName;
  int? _givenHashCode;

  _ReturnsCannedResponse _defaultResponse = () => _nullResponse;

  void _setExpected(CallPair<dynamic> cannedResponse) {
    _responses.add(cannedResponse);
  }

  /// A sentinal value used as the default argument for noSuchMethod's
  /// 'returnValueForMissingStub' parameter.
  @protected
  static const deferToDefaultResponse = Object();

  /// Handles method stubbing, method call verification, and real method calls.
  ///
  /// If passed, [returnValue] will be returned during method stubbing and
  /// method call verification. This is useful in cases where the method
  /// invocation which led to `noSuchMethod` being called has a non-nullable
  /// return type.
  @override
  @visibleForTesting
  dynamic noSuchMethod(Invocation invocation,
      {Object? returnValue,
      Object? returnValueForMissingStub = deferToDefaultResponse}) {
    // noSuchMethod is that 'magic' that allows us to ignore implementing fields
    // and methods and instead define them later at compile-time per instance.
    invocation = _useMatchedInvocationIfSet(invocation);
    if (_whenInProgress) {
      _whenCall = _WhenCall(this, invocation);
      return returnValue;
    } else if (_verificationInProgress) {
      _verifyCalls.add(_VerifyCall(this, invocation));
      return returnValue;
    } else if (_untilCalledInProgress) {
      _untilCall = _UntilCall(this, invocation);
      return returnValue;
    } else {
      _ReturnsCannedResponse defaultResponse;
      if (returnValueForMissingStub == deferToDefaultResponse) {
        defaultResponse = _defaultResponse;
      } else {
        defaultResponse = () =>
            CallPair<Object?>.allInvocations((_) => returnValueForMissingStub);
      }
      _realCalls.add(RealCall(this, invocation));
      _invocationStreamController.add(invocation);
      var cannedResponse = _responses.lastWhere(
          (cr) => cr.call.matches(invocation, {}),
          orElse: defaultResponse);
      var response = cannedResponse.response(invocation);
      return response;
    }
  }

  dynamic _noSuchMethod(Invocation invocation) =>
      throw MissingStubError(invocation, this);

  @override
  int get hashCode => _givenHashCode ?? 0;

  @override
  bool operator ==(other) => (_givenHashCode != null && other is Mock)
      ? _givenHashCode == other._givenHashCode
      : identical(this, other);

  @override
  String toString() => _givenName ?? runtimeType.toString();

  String _realCallsToString([Iterable<RealCall>? realCalls]) {
    var stringRepresentations =
        (realCalls ?? _realCalls).map((call) => call.toString());
    if (stringRepresentations.any((s) => s.contains('\n'))) {
      // As each call contains newlines, put each on its own line, for better
      // readability.
      return stringRepresentations.join(',\n');
    } else {
      // A compact String should be perfect.
      return stringRepresentations.join(', ');
    }
  }

  String _unverifiedCallsToString() =>
      _realCallsToString(_realCalls.where((call) => !call.verified));
}

/// A slightly smarter fake to be used for return value on missing stubs.
/// Shows a more descriptive error message to the user that mentions not
/// only a place where a fake was used but also why it was created
/// (i.e. which stub needs to be added).
///
/// Inspired by Java's Mockito `SmartNull`.
class SmartFake {
  final Object _parent;
  final Invocation _parentInvocation;
  final StackTrace _createdStackTrace;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw FakeUsedError(
      _parentInvocation, invocation, _parent, _createdStackTrace);
  SmartFake(this._parent, this._parentInvocation)
      : _createdStackTrace = StackTrace.current;
}

class FakeUsedError extends Error {
  final Invocation parentInvocation, invocation;
  final Object receiver;
  final StackTrace createdStackTrace;
  final String _memberName;

  FakeUsedError(this.parentInvocation, this.invocation, this.receiver,
      this.createdStackTrace)
      : _memberName = _symbolToString(parentInvocation.memberName);

  @override
  String toString() => "FakeUsedError: '$_memberName'\n"
      'No stub was found which matches the argument of this method call:\n'
      '${parentInvocation.toPrettyString()}\n\n'
      'A fake object was created for this call, in the hope that it '
      "won't be ever accessed.\n"
      "Here is the stack trace where '$_memberName' was called:\n\n"
      '${createdStackTrace.toString()}\n\n'
      "However, member '${_symbolToString(invocation.memberName)}' of the "
      'created fake object was accessed.\n'
      'Add a stub for '
      "${receiver.runtimeType}.$_memberName using Mockito's 'when' API.\n";
}

/// An error which is thrown when no stub is found which matches the arguments
/// of a real method call on a mock object.
class MissingStubError extends Error {
  final Invocation invocation;
  final Object receiver;

  MissingStubError(this.invocation, this.receiver);

  @override
  String toString() =>
      "MissingStubError: '${_symbolToString(invocation.memberName)}'\n"
      'No stub was found which matches the arguments of this method call:\n'
      '${invocation.toPrettyString()}\n\n'
      "Add a stub for this method using Mockito's 'when' API, or generate the "
      '${receiver.runtimeType} mock with the @GenerateNiceMocks annotation '
      '(see '
      'https://pub.dev/documentation/mockito/latest/annotations/MockSpec-class.html).';
}

typedef _ReturnsCannedResponse = CallPair<dynamic> Function();

// When using an [ArgMatcher], we transform our invocation to have knowledge of
// which arguments are wrapped, and which ones are not. Otherwise we just use
// the existing invocation object.
Invocation _useMatchedInvocationIfSet(Invocation invocation) {
  if (_storedArgs.isNotEmpty || _storedNamedArgs.isNotEmpty) {
    invocation = _InvocationForMatchedArguments(invocation);
  }
  return invocation;
}

/// An Invocation implementation that takes arguments from [_storedArgs] and
/// [_storedNamedArgs].
class _InvocationForMatchedArguments extends Invocation {
  @override
  final Symbol memberName;
  @override
  final Map<Symbol, dynamic> namedArguments;
  @override
  final List<dynamic> positionalArguments;
  @override
  final bool isGetter;
  @override
  final bool isMethod;
  @override
  final bool isSetter;

  factory _InvocationForMatchedArguments(Invocation invocation) {
    if (_storedArgs.isEmpty && _storedNamedArgs.isEmpty) {
      throw StateError(
          '_InvocationForMatchedArguments called when no ArgMatchers have been saved.');
    }

    // Handle named arguments first, so that we can provide useful errors for
    // the various bad states. If all is well with the named arguments, then we
    // can process the positional arguments, and resort to more general errors
    // if the state is still bad.
    var namedArguments = _reconstituteNamedArgs(invocation);
    var positionalArguments = _reconstitutePositionalArgs(invocation);

    _storedArgs.clear();
    _storedNamedArgs.clear();

    return _InvocationForMatchedArguments._(
        invocation.memberName,
        positionalArguments,
        namedArguments,
        invocation.isGetter,
        invocation.isMethod,
        invocation.isSetter);
  }

  // Reconstitutes the named arguments in an invocation from
  // [_storedNamedArgs].
  //
  // The `namedArguments` in [invocation] which are null should be represented
  // by a stored value in [_storedNamedArgs].
  static Map<Symbol, dynamic> _reconstituteNamedArgs(Invocation invocation) {
    final namedArguments = <Symbol, dynamic>{};
    final storedNamedArgSymbols =
        _storedNamedArgs.keys.map((name) => Symbol(name));

    // Iterate through [invocation]'s named args, validate them, and add them
    // to the return map.
    invocation.namedArguments.forEach((name, arg) {
      if (arg == null) {
        if (!storedNamedArgSymbols.contains(name)) {
          // Either this is a parameter with default value `null`, or a `null`
          // argument was passed, or an unnamed ArgMatcher was used. Just use
          // `null`.
          namedArguments[name] = null;
        }
      } else {
        // Add each real named argument (not wrapped in an ArgMatcher).
        namedArguments[name] = arg;
      }
    });

    // Iterate through the stored named args, validate them, and add them to
    // the return map.
    _storedNamedArgs.forEach((name, arg) {
      var nameSymbol = Symbol(name);
      if (!invocation.namedArguments.containsKey(nameSymbol)) {
        // Clear things out for the next call.
        _storedArgs.clear();
        _storedNamedArgs.clear();
        throw ArgumentError(
            'An ArgumentMatcher was declared as named $name, but was not '
            'passed as an argument named $name.\n\n'
            'BAD:  when(obj.fn(anyNamed: "a")))\n'
            'GOOD: when(obj.fn(a: anyNamed: "a")))');
      }
      if (invocation.namedArguments[nameSymbol] != null) {
        // Clear things out for the next call.
        _storedArgs.clear();
        _storedNamedArgs.clear();
        throw ArgumentError(
            'An ArgumentMatcher was declared as named $name, but a different '
            'value (${invocation.namedArguments[nameSymbol]}) was passed as '
            '$name.\n\n'
            'BAD:  when(obj.fn(b: anyNamed("a")))\n'
            'GOOD: when(obj.fn(b: anyNamed("b")))');
      }
      namedArguments[nameSymbol] = arg;
    });

    return namedArguments;
  }

  static List<dynamic> _reconstitutePositionalArgs(Invocation invocation) {
    final positionalArguments = <dynamic>[];
    final nullPositionalArguments =
        invocation.positionalArguments.where((arg) => arg == null);
    if (_storedArgs.length > nullPositionalArguments.length) {
      // More _positional_ ArgMatchers were stored than were actually passed as
      // positional arguments. There are three ways this call could have been
      // parsed and resolved:
      //
      // * an ArgMatcher was passed in [invocation] as a named argument, but
      //   without a name, and thus stored in [_storedArgs], something like
      //   `when(obj.fn(a: any))`,
      // * an ArgMatcher was passed in an expression which was passed in
      //   [invocation], and thus stored in [_storedArgs], something like
      //   `when(obj.fn(Foo(any)))`, or
      // * a combination of the above.
      _storedArgs.clear();
      _storedNamedArgs.clear();
      throw ArgumentError(
          'An argument matcher (like `any`) was either not used as an '
          'immediate argument to ${invocation.memberName} (argument matchers '
          'can only be used as an argument for the very method being stubbed '
          'or verified), or was used as a named argument without the Mockito '
          '"named" API (Each argument matcher that is used as a named argument '
          'needs to specify the name of the argument it is being used in. For '
          'example: `when(obj.fn(x: anyNamed("x")))`).');
    }
    var storedIndex = 0;
    var positionalIndex = 0;
    while (storedIndex < _storedArgs.length &&
        positionalIndex < invocation.positionalArguments.length) {
      var arg = _storedArgs[storedIndex];
      if (invocation.positionalArguments[positionalIndex] == null) {
        // Add the [ArgMatcher] given to the argument matching helper.
        positionalArguments.add(arg);
        storedIndex++;
        positionalIndex++;
      } else {
        // An argument matching helper was not used; add the [ArgMatcher] from
        // [invocation].
        positionalArguments
            .add(invocation.positionalArguments[positionalIndex]);
        positionalIndex++;
      }
    }
    while (positionalIndex < invocation.positionalArguments.length) {
      // Some trailing non-ArgMatcher arguments.
      positionalArguments.add(invocation.positionalArguments[positionalIndex]);
      positionalIndex++;
    }

    return positionalArguments;
  }

  _InvocationForMatchedArguments._(this.memberName, this.positionalArguments,
      this.namedArguments, this.isGetter, this.isMethod, this.isSetter);
}

@Deprecated(
    'This function does not provide value; hashCode and toString() can be '
    'stubbed individually. This function may be deleted as early as Mockito '
    '5.0.0')
T named<T extends Mock>(T mock, {String? name, int? hashCode}) => mock
  .._givenName = name
  .._givenHashCode = hashCode;

/// Clear stubs of, and collected interactions with [mock].
void reset(var mock) {
  mock._realCalls.clear();
  mock._responses.clear();
}

/// Clear the collected interactions with [mock].
void clearInteractions(var mock) {
  mock._realCalls.clear();
}

class PostExpectation<T> {
  /// Store a canned response for this method stub.
  ///
  /// Note: [expected] cannot be a Future or Stream, due to Zone considerations.
  /// To return a Future or Stream from a method stub, use [thenAnswer].
  void thenReturn(T expected) {
    if (expected is Future) {
      throw ArgumentError('`thenReturn` should not be used to return a Future. '
          'Instead, use `thenAnswer((_) => future)`.');
    }
    if (expected is Stream) {
      throw ArgumentError('`thenReturn` should not be used to return a Stream. '
          'Instead, use `thenAnswer((_) => stream)`.');
    }
    return _completeWhen((_) => expected);
  }

  /// Store an exception to throw when this method stub is called.
  void thenThrow(Object throwable) {
    return _completeWhen((Invocation _) {
      throw throwable;
    });
  }

  /// Store a function which is called when this method stub is called.
  ///
  /// The function will be called, and the return value will be returned.
  void thenAnswer(Answering<T> answer) {
    return _completeWhen(answer);
  }

  void _completeWhen(Answering<T> answer) {
    if (_whenCall == null) {
      throw StateError(
          'No method stub was called from within `when()`. Was a real method '
          'called, or perhaps an extension method?');
    }
    _whenCall!._setExpected<T>(answer);
    _whenCall = null;
    _whenInProgress = false;
  }
}

class InvocationMatcher {
  final Invocation roleInvocation;

  InvocationMatcher(this.roleInvocation);

  bool matches(Invocation invocation) {
    var isMatching =
        _isMethodMatches(invocation) && _isArgumentsMatches(invocation);
    if (isMatching) {
      _captureArguments(invocation);
    }
    return isMatching;
  }

  bool _isMethodMatches(Invocation invocation) {
    if (invocation.memberName != roleInvocation.memberName) {
      return false;
    }
    if ((invocation.isGetter != roleInvocation.isGetter) ||
        (invocation.isSetter != roleInvocation.isSetter) ||
        (invocation.isMethod != roleInvocation.isMethod)) {
      return false;
    }
    return true;
  }

  void _captureArguments(Invocation invocation) {
    var index = 0;
    for (var roleArg in roleInvocation.positionalArguments) {
      var actArg = invocation.positionalArguments[index];
      if (roleArg is ArgMatcher && roleArg._capture) {
        _capturedArgs.add(actArg);
      }
      index++;
    }
    for (var roleKey in roleInvocation.namedArguments.keys) {
      var roleArg = roleInvocation.namedArguments[roleKey];
      var actArg = invocation.namedArguments[roleKey];
      if (roleArg is ArgMatcher && roleArg._capture) {
        _capturedArgs.add(actArg);
      }
    }
  }

  bool _isArgumentsMatches(Invocation invocation) {
    if (invocation.positionalArguments.length !=
        roleInvocation.positionalArguments.length) {
      return false;
    }
    if (invocation.namedArguments.length !=
        roleInvocation.namedArguments.length) {
      return false;
    }
    var index = 0;
    for (var roleArg in roleInvocation.positionalArguments) {
      var actArg = invocation.positionalArguments[index];
      if (!isMatchingArg(roleArg, actArg)) {
        return false;
      }
      index++;
    }
    Set roleKeys = roleInvocation.namedArguments.keys.toSet();
    Set actKeys = invocation.namedArguments.keys.toSet();
    if (roleKeys.difference(actKeys).isNotEmpty ||
        actKeys.difference(roleKeys).isNotEmpty) {
      return false;
    }
    for (var roleKey in roleInvocation.namedArguments.keys) {
      var roleArg = roleInvocation.namedArguments[roleKey];
      var actArg = invocation.namedArguments[roleKey];
      if (!isMatchingArg(roleArg, actArg)) {
        return false;
      }
    }
    return true;
  }

  bool isMatchingArg(roleArg, actArg) {
    if (roleArg is ArgMatcher) {
      return roleArg.matcher.matches(actArg, {});
    } else {
      return equals(roleArg).matches(actArg, {});
    }
  }
}

class _TimeStampProvider {
  int _now = 0;
  DateTime now() {
    var candidate = DateTime.now();
    if (candidate.millisecondsSinceEpoch <= _now) {
      candidate = DateTime.fromMillisecondsSinceEpoch(_now + 1);
    }
    _now = candidate.millisecondsSinceEpoch;
    return candidate;
  }
}

class RealCall {
  final Mock mock;
  final Invocation invocation;
  final DateTime timeStamp;

  bool verified = false;

  RealCall(this.mock, this.invocation) : timeStamp = _timer.now();

  @override
  String toString() {
    var verifiedText = verified ? '[VERIFIED] ' : '';
    return '$verifiedText$mock.${invocation.toPrettyString()}';
  }
}

// Converts a [Symbol] to a meaningful [String].
String _symbolToString(Symbol symbol) => symbol.toString().split('"')[1];

class _WhenCall {
  final Mock mock;
  final Invocation whenInvocation;
  _WhenCall(this.mock, this.whenInvocation);

  void _setExpected<T>(Answering<T> answer) {
    mock._setExpected(CallPair<T>(isInvocation(whenInvocation), answer));
  }
}

class _UntilCall {
  final InvocationMatcher _invocationMatcher;
  final Mock _mock;

  _UntilCall(this._mock, Invocation invocation)
      : _invocationMatcher = InvocationMatcher(invocation);

  bool _matchesInvocation(RealCall realCall) =>
      _invocationMatcher.matches(realCall.invocation);

  List<RealCall> get _realCalls => _mock._realCalls;

  Future<Invocation> get invocationFuture {
    if (_realCalls.any(_matchesInvocation)) {
      return Future.value(_realCalls.firstWhere(_matchesInvocation).invocation);
    }

    return _mock._invocationStreamController.stream
        .firstWhere(_invocationMatcher.matches);
  }
}

/// A simple struct for storing a [RealCall] and any [capturedArgs] stored
/// during [InvocationMatcher.matches].
class _RealCallWithCapturedArgs {
  final RealCall realCall;
  final List<Object?> capturedArgs;

  _RealCallWithCapturedArgs(this.realCall, this.capturedArgs);
}

class _VerifyCall {
  final Mock mock;
  final Invocation verifyInvocation;
  final List<_RealCallWithCapturedArgs> matchingInvocations;
  final List<Object?> matchingCapturedArgs;

  factory _VerifyCall(Mock mock, Invocation verifyInvocation) {
    var expectedMatcher = InvocationMatcher(verifyInvocation);
    var matchingInvocations = <_RealCallWithCapturedArgs>[];
    for (var realCall in mock._realCalls) {
      if (!realCall.verified && expectedMatcher.matches(realCall.invocation)) {
        // [Invocation.matcher] collects captured arguments if
        // [verifyInvocation] included capturing matchers.
        matchingInvocations
            .add(_RealCallWithCapturedArgs(realCall, [..._capturedArgs]));
        _capturedArgs.clear();
      }
    }

    var matchingCapturedArgs = [
      for (var invocation in matchingInvocations) ...invocation.capturedArgs,
    ];

    return _VerifyCall._(
        mock, verifyInvocation, matchingInvocations, matchingCapturedArgs);
  }

  _VerifyCall._(this.mock, this.verifyInvocation, this.matchingInvocations,
      this.matchingCapturedArgs);

  _RealCallWithCapturedArgs _findAfter(DateTime time) {
    return matchingInvocations.firstWhere((invocation) =>
        !invocation.realCall.verified &&
        invocation.realCall.timeStamp.isAfter(time));
  }

  void _checkWith(bool never) {
    if (!never && matchingInvocations.isEmpty) {
      String message;
      if (mock._realCalls.isEmpty) {
        message = 'No matching calls (actually, no calls at all).';
      } else {
        var otherCalls = mock._realCallsToString();
        message = 'No matching calls. All calls: $otherCalls';
      }
      fail('$message\n'
          '(If you called `verify(...).called(0);`, please instead use '
          '`verifyNever(...);`.)');
    }
    if (never && matchingInvocations.isNotEmpty) {
      var calls = mock._unverifiedCallsToString();
      fail('Unexpected calls: $calls');
    }
    for (var invocation in matchingInvocations) {
      invocation.realCall.verified = true;
    }
  }

  @override
  String toString() =>
      'VerifyCall<mock: $mock, memberName: ${verifyInvocation.memberName}>';
}

// An argument matcher that acts like an argument during stubbing or
// verification, and stores "matching" information.
//
/// Users do not need to construct this manually; users can instead use the
/// built-in values, [any], [anyNamed], [captureAny], [captureAnyNamed], or the
/// functions [argThat] and [captureThat].
class ArgMatcher {
  final Matcher matcher;
  final bool _capture;

  ArgMatcher(this.matcher, this._capture);

  @override
  String toString() => '$ArgMatcher {$matcher: $_capture}';
}

/// An argument matcher that matches any argument passed in this argument
/// position.
///
/// See the README section on
/// [argument matchers](https://pub.dev/packages/mockito#argument-matchers)
/// for examples.
Null get any => _registerMatcher(anything, false, argumentMatcher: 'any');

/// An argument matcher that matches any named argument passed in for the
/// parameter named [named].
///
/// See the README section on
/// [named argument matchers](https://pub.dev/packages/mockito#named-arguments)
/// for examples.
Null anyNamed(String named) => _registerMatcher(anything, false,
    named: named, argumentMatcher: 'anyNamed');

/// An argument matcher that matches any argument passed in this argument
/// position, and captures the argument for later access with
/// [VerificationResult.captured].
///
/// See the README section on
/// [capturing arguments](https://pub.dev/packages/mockito#capturing-arguments-for-further-assertions)
/// for examples.
Null get captureAny =>
    _registerMatcher(anything, true, argumentMatcher: 'captureAny');

/// An argument matcher that matches any named argument passed in for the
/// parameter named [named], and captures the argument for later access with
/// [VerificationResult.captured].
///
/// See the README section on
/// [capturing arguments](https://pub.dev/packages/mockito#capturing-arguments-for-further-assertions)
/// for examples.
Null captureAnyNamed(String named) => _registerMatcher(anything, true,
    named: named, argumentMatcher: 'captureAnyNamed');

/// An argument matcher that matches an argument (named or positional) that
/// matches [matcher].

/// When capturing a named argument, the name of the argument must be passed via
/// [named].
///
/// See the README section on
/// [argument matchers](https://pub.dev/packages/mockito#argument-matchers)
/// for examples.
Null argThat(Matcher matcher, {String? named}) =>
    _registerMatcher(matcher, false, named: named, argumentMatcher: 'argThat');

/// An argument matcher that matches an argument (named or positional) that
/// matches [matcher], and captures the argument for later access with
/// [VerificationResult.captured].

/// When capturing a named argument, the name of the argument must be passed via
/// [named].
///
/// See the README section on
/// [capturing arguments](https://pub.dev/packages/mockito#capturing-arguments-for-further-assertions)
/// for examples.
Null captureThat(Matcher matcher, {String? named}) =>
    _registerMatcher(matcher, true,
        named: named, argumentMatcher: 'captureThat');

/// Registers [matcher] into the stored arguments collections.
///
/// Creates an [ArgMatcher] with [matcher] and [capture], then if [named] is
/// non-null, stores that into the positional stored arguments list; otherwise
/// stores it into the named stored arguments map, keyed on [named].
/// [argumentMatcher] is the name of the public API used to register [matcher],
/// for error messages.
Null _registerMatcher(Matcher matcher, bool capture,
    {String? named, String? argumentMatcher}) {
  if (!_whenInProgress && !_untilCalledInProgress && !_verificationInProgress) {
    // It is not meaningful to store argument matchers outside of stubbing
    // (`when`), or verification (`verify` and `untilCalled`). Such argument
    // matchers will be processed later erroneously.
    _storedArgs.clear();
    _storedNamedArgs.clear();
    throw ArgumentError(
        'The "$argumentMatcher" argument matcher is used outside of method '
        'stubbing (via `when`) or verification (via `verify` or `untilCalled`). '
        'This is invalid, and results in bad behavior during the next stubbing '
        'or verification.');
  }
  var argMatcher = ArgMatcher(matcher, capture);
  if (named == null) {
    _storedArgs.add(argMatcher);
  } else {
    _storedNamedArgs[named] = argMatcher;
  }
  return null;
}

/// Information about a stub call verification.
///
/// This class is most useful to users in two ways:
///
/// * verifying call count, via [called],
/// * collecting captured arguments, via [captured].
class VerificationResult {
  List<dynamic> _captured;

  /// List of all arguments captured in real calls.
  ///
  /// This list will include any captured default arguments and has no
  /// structure differentiating the arguments of one call from another. Given
  /// the following class:
  ///
  /// ```dart
  /// class C {
  ///   String methodWithPositionalArgs(int x, [int y]) => '';
  ///   String methodWithTwoNamedArgs(int x, {int y, int z}) => '';
  /// }
  /// ```
  ///
  /// the following stub calls will result in the following captured arguments:
  ///
  /// ```dart
  /// mock.methodWithPositionalArgs(1);
  /// mock.methodWithPositionalArgs(2, 3);
  /// var captured = verify(
  ///     mock.methodWithPositionalArgs(captureAny, captureAny)).captured;
  /// print(captured); // Prints "[1, null, 2, 3]"
  ///
  /// mock.methodWithTwoNamedArgs(1, y: 42, z: 43);
  /// mock.methodWithTwoNamedArgs(1, y: 44, z: 45);
  /// var captured = verify(
  ///     mock.methodWithTwoNamedArgs(any,
  ///         y: captureAnyNamed('y'), z: captureAnyNamed('z'))).captured;
  /// print(captured); // Prints "[42, 43, 44, 45]"
  /// ```
  ///
  /// Named arguments are listed in the order they are captured in, not the
  /// order in which they were passed.
  List<dynamic> get captured => _captured;

  @Deprecated(
      'captured should be considered final - assigning this field may be '
      'removed as early as Mockito 5.0.0')
  // ignore: unnecessary_getters_setters
  set captured(List<dynamic> captured) => _captured = captured;

  /// The number of calls matched in this verification.
  int callCount;

  bool _testApiMismatchHasBeenChecked = false;

  VerificationResult._(this.callCount, this._captured);

  /// Assert that the number of calls matches [matcher].
  ///
  /// Examples:
  ///
  /// * `verify(mock.m()).called(1)` asserts that `m()` is called exactly once.
  /// * `verify(mock.m()).called(greaterThan(2))` asserts that `m()` is called
  ///   more than two times.
  ///
  /// To assert that a method was called zero times, use [verifyNever].
  void called(dynamic matcher) {
    if (!_testApiMismatchHasBeenChecked) {
      // Only execute the check below once. `Invoker.current` may look like a
      // cheap getter, but it involves Zones and casting.
      _testApiMismatchHasBeenChecked = true;
    }
    expect(callCount, wrapMatcher(matcher),
        reason: 'Unexpected number of calls');
  }
}

typedef Answering<T> = T Function(Invocation realInvocation);

typedef Verification = VerificationResult Function<T>(T matchingInvocations);

typedef _InOrderVerification = List<VerificationResult> Function<T>(
    List<T> recordedInvocations);

/// Verify that a method on a mock object was never called with the given
/// arguments.
///
/// Call a method on a mock object within a `verifyNever` call. For example:
///
/// ```dart
/// cat.eatFood("chicken");
/// verifyNever(cat.eatFood("fish"));
/// ```
///
/// Mockito will pass the current test case, as `cat.eatFood` has not been
/// called with `"chicken"`.
Verification get verifyNever => _makeVerify(true);

/// Verify that a method on a mock object was called with the given arguments.
///
/// Call a method on a mock object within the call to `verify`. For example:
///
/// ```dart
/// cat.eatFood("chicken");
/// verify(cat.eatFood("fish"));
/// ```
///
/// Mockito will fail the current test case if `cat.eatFood` has not been called
/// with `"fish"`. Optionally, call `called` on the result, to verify that the
/// method was called a certain number of times. For example:
///
/// ```dart
/// verify(cat.eatFood("fish")).called(2);
/// verify(cat.eatFood("fish")).called(greaterThan(3));
/// ```
///
/// Note: When mockito verifies a method call, said call is then excluded from
/// further verifications. A single method call cannot be verified from multiple
/// calls to `verify`, or `verifyInOrder`. See more details in the FAQ.
///
/// Note: because of an unintended limitation, `verify(...).called(0);` will
/// not work as expected. Please use `verifyNever(...);` instead.
///
/// See also: [verifyNever], [verifyInOrder], [verifyZeroInteractions], and
/// [verifyNoMoreInteractions].
Verification get verify => _makeVerify(false);

Verification _makeVerify(bool never) {
  if (_verifyCalls.isNotEmpty) {
    var message = 'Verification appears to be in progress.';
    if (_verifyCalls.length == 1) {
      message =
          '$message One verify call has been stored: ${_verifyCalls.single}';
    } else {
      message =
          '$message ${_verifyCalls.length} verify calls have been stored. '
          '[${_verifyCalls.first}, ..., ${_verifyCalls.last}]';
    }
    throw StateError(message);
  }
  if (_verificationInProgress) {
    fail('There is already a verification in progress, '
        'check if it was not called with a verify argument(s)');
  }
  _verificationInProgress = true;
  return <T>(T mock) {
    _verificationInProgress = false;
    if (_verifyCalls.length == 1) {
      var verifyCall = _verifyCalls.removeLast();
      var result = VerificationResult._(verifyCall.matchingInvocations.length,
          verifyCall.matchingCapturedArgs);
      verifyCall._checkWith(never);
      return result;
    } else {
      fail('Used on a non-mockito object');
    }
  };
}

/// Verifies that a list of methods on a mock object have been called with the
/// given arguments. For example:
///
/// ```dart
/// verifyInOrder([cat.eatFood("Milk"), cat.sound(), cat.eatFood(any)]);
/// ```
///
/// This verifies that `eatFood` was called with `"Milk"`, `sound` was called
/// with no arguments, and `eatFood` was then called with some argument.
///
/// Returns a list of verification results, one for each call which was
/// verified.
///
/// For example, if [verifyInOrder] is given these calls to verify:
///
/// ```dart
/// var verification = verifyInOrder(
///     [cat.eatFood(captureAny), cat.chew(), cat.eatFood(captureAny)]);
/// ```
///
/// then `verification` is a list which contains a `captured` getter which
/// returns three lists:
///
/// 1. a list containing the argument passed to `eatFood` in the first
///    verified `eatFood` call,
/// 2. an empty list, as nothing was captured in the verified `chew` call,
/// 3. a list containing the argument passed to `eatFood` in the second
///    verified `eatFood` call.
///
/// Note: [verifyInOrder] only verifies that each call was made in the order
/// given, but not that those were the only calls. In the example above, if
/// other calls were made to `eatFood` or `sound` between the three given
/// calls, or before or after them, the verification will still succeed.
_InOrderVerification get verifyInOrder {
  if (_verifyCalls.isNotEmpty) {
    throw StateError(_verifyCalls.join());
  }
  _verificationInProgress = true;
  return <T>(List<T> responses) {
    if (responses.length != _verifyCalls.length) {
      fail("'verifyInOrder' called with non-mockito stub calls; List contains "
          '${responses.length} elements, but ${_verifyCalls.length} stub calls '
          'were stored: $_verifyCalls');
    }
    _verificationInProgress = false;
    var verificationResults = <VerificationResult>[];
    var time = DateTime.fromMillisecondsSinceEpoch(0);
    var tmpVerifyCalls = List<_VerifyCall>.from(_verifyCalls);
    _verifyCalls.clear();
    var matchedCalls = <RealCall>[];
    for (var verifyCall in tmpVerifyCalls) {
      try {
        var matched = verifyCall._findAfter(time);
        matchedCalls.add(matched.realCall);
        verificationResults.add(VerificationResult._(1, matched.capturedArgs));
        time = matched.realCall.timeStamp;
      } on StateError {
        var mocks = tmpVerifyCalls.map((vc) => vc.mock).toSet();
        var allInvocations =
            mocks.expand((m) => m._realCalls).toList(growable: false);
        allInvocations
            .sort((inv1, inv2) => inv1.timeStamp.compareTo(inv2.timeStamp));
        var otherCalls = '';
        if (allInvocations.isNotEmpty) {
          otherCalls = " All calls: ${allInvocations.join(", ")}";
        }
        fail('Matching call #${tmpVerifyCalls.indexOf(verifyCall)} '
            'not found.$otherCalls');
      }
    }
    for (var call in matchedCalls) {
      call.verified = true;
    }
    return verificationResults;
  };
}

void _throwMockArgumentError(String method, var nonMockInstance) {
  if (nonMockInstance == null) {
    throw ArgumentError('$method was called with a null argument');
  }
  throw ArgumentError('$method must only be given a Mock object');
}

void verifyNoMoreInteractions(var mock) {
  if (mock is Mock) {
    var unverified = mock._realCalls.where((inv) => !inv.verified).toList();
    if (unverified.isNotEmpty) {
      fail('No more calls expected, but following found: ' + unverified.join());
    }
  } else {
    _throwMockArgumentError('verifyNoMoreInteractions', mock);
  }
}

void verifyZeroInteractions(var mock) {
  if (mock is Mock) {
    if (mock._realCalls.isNotEmpty) {
      fail('No interaction expected, but following found: ' +
          mock._realCalls.join());
    }
  } else {
    _throwMockArgumentError('verifyZeroInteractions', mock);
  }
}

typedef Expectation = PostExpectation<T> Function<T>(T x);

/// Create a stub method response.
///
/// Call a method on a mock object within the call to `when`, and call a
/// canned response method on the result. For example:
///
/// ```dart
/// when(cat.eatFood("fish")).thenReturn(true);
/// ```
///
/// Mockito will store the fake call to `cat.eatFood`, and pair the exact
/// arguments given with the response. When `cat.eatFood` is called outside a
/// `when` or `verify` context (a call "for real"), Mockito will respond with
/// the stored canned response, if it can match the mock method parameters.
///
/// The response generators include `thenReturn`, `thenAnswer`, and `thenThrow`.
///
/// See the README for more information.
Expectation get when {
  if (_whenCall != null) {
    throw StateError('Cannot call `when` within a stub response');
  }
  _whenInProgress = true;
  return <T>(T _) {
    _whenInProgress = false;
    return PostExpectation<T>();
  };
}

typedef InvocationLoader = Future<Invocation> Function<T>(T _);

/// Returns a future [Invocation] that will complete upon the first occurrence
/// of the given invocation.
///
/// Usage of this is as follows:
///
/// ```dart
/// cat.eatFood("fish");
/// await untilCalled(cat.chew());
/// ```
///
/// In the above example, the untilCalled(cat.chew()) will complete only when
/// that method is called. If the given invocation has already been called, the
/// future will return immediately.
InvocationLoader get untilCalled {
  _untilCalledInProgress = true;
  return <T>(T _) {
    _untilCalledInProgress = false;
    return _untilCall!.invocationFuture;
  };
}

/// Print all collected invocations of any mock methods of [mocks].
void logInvocations(List<Mock> mocks) {
  var allInvocations =
      mocks.expand((m) => m._realCalls).toList(growable: false);
  allInvocations.sort((inv1, inv2) => inv1.timeStamp.compareTo(inv2.timeStamp));
  allInvocations.forEach((inv) {
    print(inv.toString());
  });
}

/// Reset the state of Mockito, typically for use between tests.
///
/// For example, when using the test package, mock methods may accumulate calls
/// in a `setUp` method, making it hard to verify method calls that were made
/// _during_ an individual test. Or, there may be unverified calls from previous
/// test cases that should not affect later test cases.
///
/// In these cases, [resetMockitoState] might be called at the end of `setUp`,
/// or in `tearDown`.
void resetMockitoState() {
  _whenInProgress = false;
  _untilCalledInProgress = false;
  _verificationInProgress = false;
  _whenCall = null;
  _untilCall = null;
  _verifyCalls.clear();
  _capturedArgs.clear();
  _storedArgs.clear();
  _storedNamedArgs.clear();
}

extension on Invocation {
  /// Returns a pretty String representing a method (or getter or setter) call
  /// including its arguments, separating elements with newlines when it should
  /// improve readability.
  String toPrettyString() {
    String argString;
    // Add quotes around strings to clarify the type of the argument to the user
    // and so the empty string is represented.
    var args = positionalArguments.map((v) => v is String ? "'$v'" : '$v');
    if (args.any((arg) => arg.contains('\n'))) {
      // As one or more arg contains newlines, put each on its own line, and
      // indent each, for better readability.
      argString = '\n' +
          args
              .map((arg) => arg.splitMapJoin('\n', onNonMatch: (m) => '    $m'))
              .join(',\n');
    } else {
      // A compact String should be perfect.
      argString = args.join(', ');
    }
    if (namedArguments.isNotEmpty) {
      if (argString.isNotEmpty) argString += ', ';
      var namedArgs = namedArguments.keys
          .map((key) => '${_symbolToString(key)}: ${namedArguments[key]}');
      if (namedArgs.any((arg) => arg.contains('\n'))) {
        // As one or more arg contains newlines, put each on its own line, and
        // indent each, for better readability.
        namedArgs = namedArgs
            .map((arg) => arg.splitMapJoin('\n', onNonMatch: (m) => '    $m'));
        argString += '{\n${namedArgs.join(',\n')}}';
      } else {
        // A compact String should be perfect.
        argString += '{${namedArgs.join(', ')}}';
      }
    }

    var method = _symbolToString(memberName);
    if (isMethod) {
      method = '$method($argString)';
    } else if (isGetter) {
      method = '$method';
    } else if (isSetter) {
      method = '$method=$argString';
    } else {
      throw StateError('Invocation should be getter, setter or a method call.');
    }

    return method;
  }
}

extension ListOfVerificationResult on List<VerificationResult> {
  /// Returns the list of argument lists which were captured within
  /// [verifyInOrder].
  List<List<dynamic>> get captured => [...map((result) => result.captured)];
}
