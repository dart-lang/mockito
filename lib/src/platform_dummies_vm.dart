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

import 'dart:io';
import 'dart:isolate';

import 'dummies.dart' show DummyBuilder;
import 'mock.dart' show SmartFake;

class FakeSendPort extends SmartFake implements SendPort {
  FakeSendPort(super.parent, super.invocation);
}

Map<Type, DummyBuilder> platformDummies = {
  ProcessResult:
      (parent, invocation) => ProcessResult(0, 0, '', '''
dummy ProcessResult created for a call to $parent.${invocation.memberName}'''),
  // We can't fake `Isolate`, but we can fake `SendPort`, so use it.
  Isolate: (parent, invocation) => Isolate(FakeSendPort(parent, invocation)),
};
