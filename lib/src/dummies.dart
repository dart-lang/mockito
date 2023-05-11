// Copyright 2023 Dart Mockito authors
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

import 'dart:async';
import 'dart:typed_data';
import 'mock.dart' show FakeFunctionUsedError;
import 'platform_dummies_common.dart'
    if (dart.library.io) 'platform_dummies_nonjs.dart';

// TODO(yanok): try to change these to _unreasonable_ values, for example,
// String could totally contain an explanation.
const int _dummyInt = 0;
const double _dummyDouble = 0.0;
const String _dummyString = '';

// This covers functions with up to 20 positional arguments, for more arguments
// or for named arguments we rely on the codegen.
Never Function([
  Object? arg1,
  Object? arg2,
  Object? arg3,
  Object? arg4,
  Object? arg5,
  Object? arg6,
  Object? arg7,
  Object? arg8,
  Object? arg9,
  Object? arg10,
  Object? arg11,
  Object? arg12,
  Object? arg13,
  Object? arg14,
  Object? arg15,
  Object? arg16,
  Object? arg17,
  Object? arg18,
  Object? arg19,
  Object? arg20,
]) _dummyFunction(Object parent, Invocation invocation) {
  final stackTrace = StackTrace.current;
  return ([
    arg1,
    arg2,
    arg3,
    arg4,
    arg5,
    arg6,
    arg7,
    arg8,
    arg9,
    arg10,
    arg11,
    arg12,
    arg13,
    arg14,
    arg15,
    arg16,
    arg17,
    arg18,
    arg19,
    arg20,
  ]) =>
      throw FakeFunctionUsedError(invocation, parent, stackTrace);
}

class MissingDummyValueError {
  final Type type;
  MissingDummyValueError(this.type);
  @override
  String toString() => '''
MissingDummyValueError: $type

This means Mockito was not smart enough to generate a dummy value of type
'$type'. Please consider using either 'provideDummy' or 'provideDummyBuilder'
functions to give Mockito a proper dummy value.

Please note that due to implementation details Mockito sometimes needs users
to provide dummy values for some types, even if they plan to explicitly stub
all the called methods.
''';
}

abstract class Dummy {
  Object? value(Object parent, Invocation invocation);
  const Dummy();
}

class DummyFor<T> extends Dummy {
  @override
  T value(Object parent, Invocation invocation) =>
      _dummyValue(parent, invocation);
  const DummyFor();
}

class DummyForFuture<T> extends DummyFor<Future<T>> {
  @override
  Future<T> value(Object parent, Invocation invocation) =>
      Future.value(_dummyValue(parent, invocation));
}

typedef _DummyBuilder = Object? Function(Object, Invocation);

Map<Type, _DummyBuilder> _dummyBuilders = {};

List<Object?> _defaultDummies = [
  // Nullable things can always be null.
  null,
  // Core types.
  false,
  _dummyInt,
  _dummyDouble,
  _dummyString,
  // This covers functions without named or type arguments, with up to 20
  // positional arguments. For others we rely on codegen to create a proper
  // builder.
  _dummyFunction,
  // Core containers.
  <Never>[],
  <Never>{},
  <Never, Never>{},
  Stream<Never>.empty(),
  // dart:typed_data classes.
  Int8List(0),
  Int16List(0),
  Int32List(0),
  Uint8List(0),
  Uint16List(0),
  Uint32List(0),
  Float32List(0),
  Float64List(0),
  ByteData(0),
  ...platformDummies,
];

T _dummyValue<T>(Object parent, Invocation invocation) {
  if (_dummyBuilders.containsKey(T)) {
    return _dummyBuilders[T]!(parent, invocation) as T;
  }
  for (var value in _defaultDummies) {
    if (value is _DummyBuilder) value = value(parent, invocation);
    if (value is T) return value;
  }
  throw MissingDummyValueError(T);
}

void provideDummyBuilder<T>(T Function(Object, Invocation) builder) =>
    _dummyBuilders[T] = builder;

void provideDummy<T>(T value) => provideDummyBuilder((_p, _i) => value);
