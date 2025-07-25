// Copyright 2019 Dart Mockito authors
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

@TestOn('vm')
library;

import 'dart:convert' show utf8;

import 'package:build/build.dart';
import 'package:build/experiments.dart';
import 'package:build_test/build_test.dart';
import 'package:mockito/src/builder.dart';
import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

import 'contains_ignoring_formatting.dart';

const annotationsAsset = {
  'mockito|lib/annotations.dart': '''
class GenerateMocks {
  final List<Type> classes;
  final List<MockSpec> customMocks;

  const GenerateMocks(this.classes, {this.customMocks = const []});
}

class MockSpec<T> {
  final Symbol? mockName;

  final Set<Symbol> unsupportedMembers;

  final Map<Symbol, Function> fallbackGenerators;

  const MockSpec({
    Symbol? as,
    this.unsupportedMembers = const {},
    this.fallbackGenerators = const {},
  })
      : mockName = as;
}
''',
};

const mockitoAssets = {
  'mockito|lib/mockito.dart': '''
export 'src/mock.dart';
''',
  'mockito|lib/src/mock.dart': '''
class Mock {}
''',
};

const metaAssets = {
  'meta|lib/meta.dart': '''
library meta;
class _Immutable {
  const _Immutable();
}
const immutable = _Immutable();
''',
};

const simpleTestAsset = {
  'foo|test/foo_test.dart': '''
import 'package:foo/foo.dart';
import 'package:mockito/annotations.dart';
@GenerateMocks([Foo])
void main() {}
''',
};

void main() {
  late InMemoryAssetWriter writer;

  /// Test [MockBuilder] in a package which has opted into null safety.
  Future<void> testWithNonNullable(
    Map<String, String> sourceAssets, {
    Map<String, /*String|Matcher<List<int>>*/ Object>? outputs,
    Map<String, dynamic> config = const <String, dynamic>{},
  }) async {
    final packageConfig = PackageConfig([
      Package(
        'foo',
        Uri.file('/foo/'),
        packageUriRoot: Uri.file('/foo/lib/'),
        languageVersion: LanguageVersion(3, 3),
      ),
    ]);
    await testBuilder(
      buildMocks(BuilderOptions(config)),
      sourceAssets,
      writer: writer,
      outputs: outputs,
      packageConfig: packageConfig,
    );
  }

  /// Builds with [MockBuilder] in a package which has opted into null safety,
  /// returning the content of the generated mocks library.
  Future<String> buildWithNonNullable(Map<String, String> sourceAssets) async {
    final packageConfig = PackageConfig([
      Package(
        'foo',
        Uri.file('/foo/'),
        packageUriRoot: Uri.file('/foo/lib/'),
        languageVersion: LanguageVersion(3, 3),
      ),
    ]);

    await testBuilder(
      buildMocks(BuilderOptions({})),
      sourceAssets,
      writer: writer,
      packageConfig: packageConfig,
    );
    final mocksAsset = AssetId('foo', 'test/foo_test.mocks.dart');
    return utf8.decode(writer.assets[mocksAsset]!);
  }

  /// Test [MockBuilder] on a single source file, in a package which has opted
  /// into null safety, and with the non-nullable experiment enabled.
  Future<void> expectSingleNonNullableOutput(
    String sourceAssetText,
    /*String|Matcher<List<int>>*/ Object output,
  ) async {
    await testWithNonNullable(
      {
        ...metaAssets,
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': sourceAssetText,
      },
      outputs: {'foo|test/foo_test.mocks.dart': output},
    );
  }

  /// Builds with [MockBuilder] in a package which has opted into the
  /// non-nullable type system, returning the content of the generated mocks
  /// library.
  Future<String> buildWithSingleNonNullableSource(
    String sourceAssetText,
  ) async {
    await testWithNonNullable({
      ...annotationsAsset,
      ...simpleTestAsset,
      'foo|lib/foo.dart': sourceAssetText,
    });
    final mocksAsset = AssetId('foo', 'test/foo_test.mocks.dart');
    return utf8.decode(writer.assets[mocksAsset]!);
  }

  setUp(() {
    writer = InMemoryAssetWriter();
  });

  test(
    'generates a mock class but does not override methods w/ zero parameters',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      class Foo {
        dynamic method1() => 7;
      }
      '''),
      );
      expect(
        mocksContent,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test(
    'generates a mock class but does not override private methods',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      class Foo {
        int _method1(int x) => 8;
      }
      '''),
      );
      expect(
        mocksContent,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test('generates a mock class but does not override static methods', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo {
        static int method1(int y) => 9;
      }
      '''),
    );
    expect(mocksContent, isNot(contains('method1')));
  });

  test(
    'generates a mock class but does not override any extension methods',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      extension X on Foo {
        dynamic x(int m, String n) => n + 1;
      }
      class Foo {}
      '''),
      );
      expect(
        mocksContent,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
      );
    },
  );

  test('overrides methods, matching required positional parameters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(int a) {}
      }
      '''),
      _containsAllOf('void m(int? a) => super.noSuchMethod('),
    );
  });

  test('overrides methods, matching optional positional parameters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(int a, [int b, int c = 0]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m(
          int? a, [
          int? b,
          int? c = 0,
        ]) =>
        '''),
      ),
    );
  });

  test('overrides methods, matching named parameters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(int a, {int b, int c = 0}) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m(
          int? a, {
          int? b,
          int? c = 0,
        }) =>
        '''),
      ),
    );
  });

  test('matches parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([int a, int b = 0]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m([
          int? a,
          int? b = 0,
        ]) =>'''),
      ),
    );
  });

  test('matches boolean literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([bool a = true, bool b = false]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m([
          bool? a = true,
          bool? b = false,
        ]) =>
        '''),
      ),
    );
  });

  test('matches number literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([int a = 0, double b = 0.5]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m([
          int? a = 0,
          double? b = 0.5,
        ]) =>
        '''),
      ),
    );
  });

  test('matches string literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([String a = 'Hello', String b = "World"]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m([
          String? a = 'Hello',
          String? b = 'World',
        ]) =>
        '''),
      ),
    );
  });

  test(
    'matches string literal parameter default values with quote characters',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        void m([String a = 'Hel"lo', String b = "Wor'ld"]) {}
      }
      '''),
        _containsAllOf(
          dedent2('''
        void m([
          String? a = 'Hel"lo',
          String? b = 'Wor\\'ld',
        ]) =>
        '''),
        ),
      );
    },
  );

  test('matches raw string literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([String a = r'$Hello', String b = r"$World"]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m([
          String? a = '\\\$Hello',
          String? b = '\\\$World',
        ]) =>
        '''),
      ),
    );
  });

  test('matches empty collection literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([List<int> a = const [], Map<int, int> b = const {}]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m([
          List<int>? a = const [],
          Map<int, int>? b = const {},
        ]) =>
        '''),
      ),
    );
  });

  test('matches non-empty list literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([List<int> a = const [1, 2, 3]]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m(
                [List<int>? a = const [
                  1,
                  2,
                  3,
                ]]) =>
        '''),
      ),
    );
  });

  test('matches non-empty map literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([Map<int, String> a = const {1: 'a', 2: 'b'}]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m(
                [Map<int, String>? a = const {
                  1: 'a',
                  2: 'b',
                }]) =>
        '''),
      ),
    );
  });

  test('matches non-empty map literal parameter default values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m([Map<int, String> a = const {1: 'a', 2: 'b'}]) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m(
                [Map<int, String>? a = const {
                  1: 'a',
                  2: 'b',
                }]) =>
        '''),
      ),
    );
  });

  test(
    'matches parameter default values constructed from a local class',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        void m([Bar a = const Bar()]) {}
      }
      class Bar {
        const Bar();
      }
      '''),
        _containsAllOf(
          'void m([_i2.Bar? a = const _i2.Bar()]) => super.noSuchMethod(',
        ),
      );
    },
  );

  test(
    'matches parameter default values constructed from a Dart SDK class',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        void m([Duration a = const Duration(days: 1)]) {}
      }
      '''),
        _containsAllOf(
          'void m([Duration? a = const Duration(days: 1)]) => super.noSuchMethod(',
        ),
      );
    },
  );

  test(
    'matches parameter default values constructed from a named constructor',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        void m([Bar a = const Bar.named()]) {}
      }
      class Bar {
        const Bar.named();
      }
      '''),
        _containsAllOf(
          'void m([_i2.Bar? a = const _i2.Bar.named()]) => super.noSuchMethod(',
        ),
      );
    },
  );

  test(
    'matches parameter default values constructed with positional arguments',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        void m([Bar a = const Bar(7)]) {}
      }
      class Bar {
        final int i;
        const Bar(this.i);
      }
      '''),
        _containsAllOf(
          'void m([_i2.Bar? a = const _i2.Bar(7)]) => super.noSuchMethod(',
        ),
      );
    },
  );

  test(
    'matches parameter default values constructed with named arguments',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        void m([Bar a = const Bar(i: 7)]) {}
      }
      class Bar {
        final int i;
        const Bar({this.i});
      }
      '''),
        _containsAllOf(
          'void m([_i2.Bar? a = const _i2.Bar(i: 7)]) => super.noSuchMethod(',
        ),
      );
    },
  );

  test(
    'matches parameter default values constructed with top-level variable',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        void m([int a = x]) {}
      }
      const x = 1;
      '''),
        _containsAllOf('void m([int? a = 1]) => super.noSuchMethod('),
      );
    },
  );

  test(
    'matches parameter default values constructed with top-level function',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      typedef Callback = void Function();
      void defaultCallback() {}
      class Foo {
        void m([Callback a = defaultCallback]) {}
      }
      '''),
        _containsAllOf(
          'void m([_i2.Callback? a = _i2.defaultCallback]) => super.noSuchMethod(',
        ),
      );
    },
  );

  test(
    'matches parameter default values constructed with static field',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        static const x = 1;
        void m([int a = x]) {}
      }
      '''),
        _containsAllOf('void m([int? a = 1]) => super.noSuchMethod('),
      );
    },
  );

  test('throws when given a parameter default value using a private type', () {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
      class Foo {
        void m([Bar a = const _Bar()]) {}
      }
      class Bar {}
      class _Bar implements Bar {
        const _Bar();
      }
      '''),
      },
      message: contains(
        "Mockito cannot generate a valid override for method 'Foo.m'; "
        "parameter 'a' causes a problem: default value has a private type: "
        'asset:foo/lib/foo.dart#_Bar',
      ),
    );
  });

  test('throws when given a parameter default value using a private type, and '
      'refers to the class-to-mock', () {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
      class FooBase {
        void m([Bar a = const _Bar()]) {}
      }
      class Foo extends FooBase {}
      class Bar {}
      class _Bar implements Bar {
        const _Bar();
      }
      '''),
      },
      message: contains(
        "Mockito cannot generate a valid override for method 'Foo.m'; "
        "parameter 'a' causes a problem: default value has a private type: "
        'asset:foo/lib/foo.dart#_Bar',
      ),
    );
  });

  test(
    'throws when given a parameter default value using a private constructor',
    () {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          ...simpleTestAsset,
          'foo|lib/foo.dart': dedent(r'''
        class Foo {
          void m([Bar a = const Bar._named()]) {}
        }
        class Bar {
          const Bar._named();
        }
        '''),
        },
        message: contains(
          "Mockito cannot generate a valid override for method 'Foo.m'; "
          "parameter 'a' causes a problem: default value has a private type: "
          'asset:foo/lib/foo.dart#Bar::_named',
        ),
      );
    },
  );

  test('throws when given a parameter default value which is a type', () {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {
          void m([Type a = int]) {}
        }
        '''),
      },
      message: contains(
        'Mockito cannot generate a valid override for method '
        "'Foo.m'; parameter 'a' causes a problem: default value is a Type: "
        'int',
      ),
    );
  });

  test('overrides async methods legally', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Future<void> m() async => print(s);
      }
      '''),
      _containsAllOf('_i3.Future<void> m() => (super.noSuchMethod('),
    );
  });

  test('overrides async* methods legally', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Stream<int> m() async* { yield 7; }
      }
      '''),
      _containsAllOf('_i3.Stream<int> m() => (super.noSuchMethod('),
    );
  });

  test('overrides sync* methods legally', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Iterable<int> m() sync* { yield 7; }
      }
      '''),
      _containsAllOf('Iterable<int> m() => (super.noSuchMethod('),
    );
  });

  test('overrides methods of super classes', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class FooBase {
        void m(int a) {}
      }
      class Foo extends FooBase {}
      '''),
      _containsAllOf('void m(int? a) => super.noSuchMethod('),
    );
  });

  test(
    'overrides methods of generic super classes, substituting types',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class FooBase<T> {
        void m(T a) {}
      }
      class Foo extends FooBase<int> {}
      '''),
        _containsAllOf('void m(int? a) => super.noSuchMethod('),
      );
    },
  );

  test('overrides methods of mixed in classes, substituting types', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Mixin<T> {
        void m(T a) {}
      }
      class Foo with Mixin<int> {}
      '''),
      _containsAllOf('void m(int? a) => super.noSuchMethod('),
    );
  });

  test('overrides methods of mixed in classes, from hierarchy', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      mixin Mixin {
        void m(int a) {}
      }
      class FooBase with Mixin {}
      class Foo extends FooBase {}
      '''),
      _containsAllOf('void m(int? a) => super.noSuchMethod('),
    );
  });

  test(
    'overrides mixed in methods, using correct overriding signature',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Base {
        void m(int a) {}
      }
      mixin MixinConstraint implements Base {}
      mixin Mixin on MixinConstraint {
        @override
        void m(num a) {}
      }
      class Foo with MixinConstraint, Mixin {}
      '''),
        _containsAllOf('void m(num? a) => super.noSuchMethod('),
      );
    },
  );

  test('overrides methods of implemented classes', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Interface<T> {
        void m(T a) {}
      }
      class Foo implements Interface<int> {}
      '''),
      _containsAllOf('void m(int? a) => super.noSuchMethod('),
    );
  });

  test('overrides fields of implemented classes', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Interface<T> {
        int m;
      }
      class Foo implements Interface<int> {}
      '''),
      _containsAllOf(
        'int get m => (super.noSuchMethod(',
        'set m(int? value) => super.noSuchMethod(',
      ),
    );
  });

  test(
    'overrides methods of indirect generic super classes, substituting types',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class FooBase2<T> {
        void m(T a) {}
      }
      class FooBase1<T> extends FooBase2<T> {}
      class Foo extends FooBase2<int> {}
      '''),
        _containsAllOf('void m(int? a) => super.noSuchMethod('),
      );
    },
  );

  test('overrides methods of generic super classes using void', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class FooBase<T> {
        T m() {}
      }
      class Foo extends FooBase<void> {}
      '''),
      _containsAllOf('void m() => super.noSuchMethod('),
    );
  });

  test('overrides methods of generic super classes (type variable)', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class FooBase<T> {
        void m(T a) {}
      }
      class Foo<T> extends FooBase<T> {}
      '''),
      _containsAllOf('void m(T? a) => super.noSuchMethod('),
    );
  });

  test(
    'overrides methods, adjusting imports for names that conflict with core',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
      import 'dart:core' as core;
      class Foo {
        void List(core.int a) {}
        core.List<core.String> m() => [];
      }
      '''),
        _containsAllOf(
          '  void List(int? a) => super.noSuchMethod(\n',
          '  _i3.List<String> m() => (super.noSuchMethod(\n',
        ),
      );
    },
  );

  test('overrides `toString` with a correct signature if the class overrides '
      'it', () async {
    await expectSingleNonNullableOutput(
      dedent('''
      abstract class Foo {
        String toString({bool a = false});
      }
      '''),
      _containsAllOf('String toString({bool? a = false}) => super.toString()'),
    );
  });

  test('does not override `toString` if the class does not override `toString` '
      'with additional parameters', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent('''
      abstract class Foo {
        String toString() => 'Foo';
      }
      '''),
    );
    expect(mocksContent, isNot(contains('toString')));
  });

  test('overrides `toString` with a correct signature if a mixed in class '
      'overrides it, in a Fake', () async {
    await expectSingleNonNullableOutput(
      dedent('''
      abstract class Foo {
        Bar m();
      }
      abstract class BarBase {
        String toString({bool a = false});
      }
      abstract class Bar extends BarBase {}
      '''),
      _containsAllOf('String toString({bool? a = false}) => super.toString()'),
    );
  });

  test(
    'does not override `operator==`, even if the class overrides it',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent('''
      class Foo {
        bool operator==(Object? other);
      }
      '''),
      );
      expect(mocksContent, isNot(contains('==')));
    },
  );

  test(
    'does not override `hashCode`, even if the class overrides it',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent('''
      class Foo {
        final int hashCode = 7;
      }
      '''),
      );
      expect(mocksContent, isNot(contains('hashCode')));
    },
  );

  test('generates mock classes from part files', () async {
    final mocksOutput = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        part 'part.dart';
        ''',
      'foo|test/part.dart': '''
        part of 'foo_test.dart';
        @GenerateMocks([Foo])
        void fooTests() {}
        ''',
    });
    expect(
      mocksOutput,
      contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
    );
  });

  test('does not crash upon finding non-library files', () async {
    await testWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent('class Foo {}'),
      'foo|test/foo_test.dart': "part 'part.dart';",
      'foo|test/part.dart': "part of 'foo_test.dart';",
    }, outputs: {});
  });

  test(
    'generates mock classes from an annotation on an import directive',
    () async {
      final mocksOutput = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'class Foo {} class Bar {}'),
        'foo|test/foo_test.dart': '''
        @GenerateMocks([Foo])
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        ''',
      });
      expect(
        mocksOutput,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
      );
    },
  );

  test(
    'generates mock classes from an annotation on an export directive',
    () async {
      final mocksOutput = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        class Bar {}
        '''),
        'foo|test/foo_test.dart': '''
        @GenerateMocks([Foo])
        export 'dart:core';
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        ''',
      });
      expect(
        mocksOutput,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
      );
    },
  );

  test('generates multiple mock classes', () async {
    final mocksOutput = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        class Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([Foo, Bar])
        void main() {}
        ''',
    });
    expect(
      mocksOutput,
      contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
    );
    expect(
      mocksOutput,
      contains('class MockBar extends _i1.Mock implements _i2.Bar'),
    );
  });

  test('generates mock classes from multiple annotations', () async {
    final mocksOutput = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        class Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([Foo])
        void fooTests() {}
        @GenerateMocks([Bar])
        void barTests() {}
        ''',
    });
    expect(
      mocksOutput,
      contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
    );
    expect(
      mocksOutput,
      contains('class MockBar extends _i1.Mock implements _i2.Bar'),
    );
  });

  test(
    'generates mock classes from multiple annotations on a single element',
    () async {
      final mocksOutput = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        class Bar {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([Foo])
        @GenerateMocks([Bar])
        void barTests() {}
        ''',
      });
      expect(
        mocksOutput,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
      );
      expect(
        mocksOutput,
        contains('class MockBar extends _i1.Mock implements _i2.Bar'),
      );
    },
  );

  test('generates generic mock classes', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo<T, U> {}
      '''),
    );
    expect(
      mocksContent,
      contains('class MockFoo<T, U> extends _i1.Mock implements _i2.Foo<T, U>'),
    );
  });

  test('generates generic mock classes with type bounds', () async {
    final mocksOutput = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        class Bar<T extends Foo> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([Foo, Bar])
        void main() {}
        ''',
    });
    expect(
      mocksOutput,
      contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
    );
    expect(
      mocksOutput,
      contains(
        'class MockBar<T extends _i2.Foo> extends _i1.Mock '
        'implements _i2.Bar<T>',
      ),
    );
  });

  test('writes dynamic, void w/o import prefix', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(dynamic a, int b) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        void m(
          dynamic a,
          int? b,
        ) =>
        '''),
      ),
    );
  });

  test('matches function parameters with scoped return types', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        class Foo {
          void m<T>(T Function() a) {}
        }
        '''),
      _containsAllOf('void m<T>(T Function()? a) => super.noSuchMethod('),
    );
  });

  test('writes type variables types w/o import prefixes', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        class Foo {
          void m<T>(T a) {}
        }
        '''),
      _containsAllOf('void m<T>(T? a) => super.noSuchMethod('),
    );
  });

  test('imports libraries for external class types', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        import 'dart:async';
        class Foo {
          dynamic f(List<Foo> list) {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'package:foo/foo.dart' as _i2;"));
    expect(mocksContent, contains('implements _i2.Foo'));
    expect(mocksContent, contains('List<_i2.Foo>? list'));
  });

  test(
    'imports libraries for external class types declared in parts',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        part 'foo_part.dart';
        '''),
        'foo|lib/foo_part.dart': dedent(r'''
        part of 'foo.dart';
        class Foo {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([Foo])
        void fooTests() {}
        ''',
      });
      expect(mocksContent, contains("import 'package:foo/foo.dart' as _i2;"));
      expect(
        mocksContent,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
      );
    },
  );

  test('imports libraries for external class types found in a method return '
      'type', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      import 'dart:async';
      class Foo {
        Future<void> f() async {}
      }
      '''),
    );
    expect(mocksContent, contains("import 'dart:async' as _i3;"));
    expect(mocksContent, contains('_i3.Future<void> f()'));
  });

  test(
    'imports libraries for external class types found in a type argument',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      import 'dart:async';
      class Foo {
        List<Future> f() => [];
      }
      '''),
      );
      expect(mocksContent, contains("import 'dart:async' as _i3;"));
      expect(mocksContent, contains('List<_i3.Future<dynamic>> f()'));
    },
  );

  test('imports libraries for external class types found in the return type of '
      'a function-typed parameter', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      import 'dart:async';
      class Foo {
        void f(Future<void> a()) {}
      }
      '''),
    );
    expect(mocksContent, contains("import 'dart:async' as _i3;"));
    expect(mocksContent, contains('f(_i3.Future<void> Function()? a)'));
  });

  test(
    'imports libraries for external class types found in a parameter type of '
    'a function-typed parameter',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      import 'dart:async';
      class Foo {
        void f(void a(Future<int> b)) {}
      }
      '''),
      );
      expect(mocksContent, contains("import 'dart:async' as _i3;"));
      expect(mocksContent, contains('f(void Function(_i3.Future<int>)? a)'));
    },
  );

  test('imports libraries for external class types found in a function-typed '
      'parameter', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        import 'dart:async';
        class Foo {
          void f(Future<void> a()) {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'dart:async' as _i3;"));
    expect(mocksContent, contains('f(_i3.Future<void> Function()? a)'));
  });

  test('imports libraries for external class types found in a FunctionType '
      'parameter', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        import 'dart:async';
        class Foo {
          void f(Future<void> Function() a) {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'dart:async' as _i3;"));
    expect(mocksContent, contains('f(_i3.Future<void> Function()? a)'));
  });

  test('imports libraries for external class types found nested in a '
      'function-typed parameter', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        import 'dart:async';
        class Foo {
          void f(void a(Future<void> b)) {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'dart:async' as _i3;"));
    expect(mocksContent, contains('f(void Function(_i3.Future<void>)? a)'));
  });

  test('imports libraries for external class types found in the bound of a '
      'type parameter of a method', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        import 'dart:async';
        class Foo {
          void f<T extends Future>(T a) {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'dart:async' as _i3;"));
    expect(mocksContent, contains('f<T extends _i3.Future<dynamic>>(T? a)'));
  });

  test('imports libraries for external class types found in the default value '
      'of a parameter', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      import 'dart:convert';
      class Foo {
        void f([Object a = utf8]) {}
      }
      '''),
    );
    expect(mocksContent, contains("import 'dart:convert' as _i3;"));
    expect(mocksContent, contains('f([Object? a = const _i3.Utf8Codec()])'));
  });

  test(
    'imports libraries for external class types found in an inherited method',
    () async {
      await testWithNonNullable({
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': '''
        import 'bar.dart';
        class Foo extends Bar {}
        ''',
        'foo|lib/bar.dart': '''
        import 'dart:async';
        class Bar {
          m(Future<void> a) {}
        }
        ''',
      });
      final mocksAsset = AssetId('foo', 'test/foo_test.mocks.dart');
      final mocksContent = utf8.decode(writer.assets[mocksAsset]!);
      expect(mocksContent, contains("import 'dart:async' as _i3;"));
      expect(mocksContent, contains('m(_i3.Future<void>? a)'));
    },
  );

  test(
    'imports libraries for external class types found in an inherited method '
    'via a generic instantiation',
    () async {
      await testWithNonNullable({
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': '''
        import 'dart:async';
        import 'bar.dart';
        class Foo extends Bar<Future<void>> {}
        ''',
        'foo|lib/bar.dart': '''
        class Bar<T> {
          m(T a) {}
        }
        ''',
      });
      final mocksAsset = AssetId('foo', 'test/foo_test.mocks.dart');
      final mocksContent = utf8.decode(writer.assets[mocksAsset]!);
      expect(mocksContent, contains("import 'dart:async' as _i3;"));
      expect(mocksContent, contains('m(_i3.Future<void>? a)'));
    },
  );

  test('imports libraries for type aliases with external types', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        import 'dart:async';
        typedef Callback = void Function();
        typedef void Callback2();
        typedef Future<T> Callback3<T>();
        class Foo {
          dynamic f(Callback c) {}
          dynamic g(Callback2 c) {}
          dynamic h(Callback3<Foo> c) {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'package:foo/foo.dart' as _i2;"));
    expect(mocksContent, contains('implements _i2.Foo'));
    expect(mocksContent, contains('_i2.Callback? c'));
    expect(mocksContent, contains('_i2.Callback2? c'));
    expect(mocksContent, contains('_i2.Callback3<_i2.Foo>? c'));
  });

  test('imports libraries for type aliases with external types 2', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        import 'dart:async';
        typedef Ignore<T> = String Function(int);
        class Foo {
          dynamic f(Ignore<Future<int>> c) {}
          dynamic g(Ignore<Future> c) {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'package:foo/foo.dart' as _i2;"));
    expect(mocksContent, contains("import 'dart:async' as _i3;"));
    expect(mocksContent, contains('implements _i2.Foo'));
    expect(mocksContent, contains('_i2.Ignore<_i3.Future<int>>? c'));
    expect(mocksContent, contains('_i2.Ignore<_i3.Future<dynamic>>? c'));
  });

  test(
    'imports libraries for types declared in private SDK libraries',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent('''
        import 'dart:io';
        abstract class Foo {
          HttpClient f() {}
        }
        '''),
      );
      expect(mocksContent, contains("import 'dart:io' as _i2;"));
      expect(mocksContent, contains('_i2.HttpClient f() =>'));
    },
  );

  test('imports libraries for types declared in private SDK libraries exported '
      'in dart:io', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent('''
        import 'dart:io';
        abstract class Foo {
          HttpStatus f() {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'dart:io' as _i2;"));
    expect(mocksContent, contains('_i2.HttpStatus f() =>'));
  });

  test('imports libraries for types declared in private SDK libraries exported '
      'in dart:html', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent('''
        import 'dart:html';
        abstract class Foo {
          HttpStatus f() {}
        }
        '''),
    );
    expect(mocksContent, contains("import 'dart:html' as _i2;"));
    expect(mocksContent, contains('_i2.HttpStatus f() =>'));
  });

  test('imports libraries which export external class types', () async {
    await testWithNonNullable({
      ...annotationsAsset,
      ...simpleTestAsset,
      'foo|lib/foo.dart': '''
        import 'types.dart';
        abstract class Foo {
          void m(Bar a);
        }
        ''',
      'foo|lib/types.dart': '''
        export 'base.dart' if (dart.library.html) 'html.dart';
        ''',
      'foo|lib/base.dart': '''
        class Bar {}
        ''',
      'foo|lib/html.dart': '''
        class Bar {}
        ''',
    });
    final mocksAsset = AssetId('foo', 'test/foo_test.mocks.dart');
    final mocksContent = utf8.decode(writer.assets[mocksAsset]!);
    expect(mocksContent, contains("import 'package:foo/types.dart' as _i3;"));
    expect(mocksContent, contains('m(_i3.Bar? a)'));
  });

  test(
    'imports dart:core with a prefix when members conflict with dart:core',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
      import 'dart:core' as core;
      class Foo {
        void List(int a) {}
        core.List<String> m() => [];
      }
      '''),
        _containsAllOf(
          "import 'dart:core' hide List;",
          "import 'dart:core' as _i3;",
        ),
      );
    },
  );

  test('prefixes parameter type on generic function-typed parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        dynamic m(void Function(Foo f) a) {}
      }
      '''),
      _containsAllOf(
        'dynamic m(void Function(_i2.Foo)? a) => super.noSuchMethod(Invocation.method(',
      ),
    );
  });

  test('prefixes return type on generic function-typed parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(Foo Function() a) {}
      }
      '''),
      _containsAllOf('void m(_i2.Foo Function()? a) => super.noSuchMethod('),
    );
  });

  test('prefixes parameter type on function-typed parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(void a(Foo f)) {}
      }
      '''),
      _containsAllOf(
        'void m(void Function(_i2.Foo)? a) => super.noSuchMethod(',
      ),
    );
  });

  test('prefixes return type on function-typed parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(Foo a()) {}
      }
      '''),
      _containsAllOf('void m(_i2.Foo Function()? a) => super.noSuchMethod('),
    );
  });

  test('renames wildcard parameters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void m(int _, int _) {}
      }
      '''),
      _containsAllOf(
        'void m(int? _0, int? _1) => super.noSuchMethod(Invocation.method(',
        'Invocation.method(#m, [_0, _1])',
      ),
    );
  });

  test('widens the type of parameters to be nullable', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          void m(int? a, int b);
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m(
          int? a,
          int? b,
        ) =>
        '''),
      ),
    );
  });

  test('widens the type of potentially non-nullable type variables to be '
      'nullable', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo<T> {
          void m(int? a, T b);
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m(
          int? a,
          T? b,
        ) =>
        '''),
      ),
    );
  });

  test('widens the type of covariant parameters to be nullable', () async {
    await expectSingleNonNullableOutput(
      dedent('''
        abstract class FooBase {
          void m(num a);
        }
        abstract class Foo extends FooBase {
          void m(covariant int a);
        }
        '''),
      _containsAllOf('void m(num? a) => super.noSuchMethod('),
    );
  });

  test(
    'widens the type of covariant parameters with default values to be nullable',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
        abstract class FooBase {
          void m([num a = 0]);
        }
        abstract class Foo extends FooBase {
          void m([covariant int a = 0]);
        }
        '''),
        _containsAllOf('void m([num? a = 0]) => super.noSuchMethod('),
      );
    },
  );

  test('widens the type of covariant parameters (declared covariant in a '
      'superclass) to be nullable', () async {
    await expectSingleNonNullableOutput(
      dedent('''
        abstract class FooBase {
          void m(covariant num a);
        }
        abstract class Foo extends FooBase {
          void m(int a);
        }
        '''),
      _containsAllOf('void m(num? a) => super.noSuchMethod('),
    );
  });

  test(
    'widens the type of successively covariant parameters to be nullable',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
        abstract class FooBaseBase {
          void m(Object a);
        }
        abstract class FooBase extends FooBaseBase {
          void m(covariant num a);
        }
        abstract class Foo extends FooBase {
          void m(covariant int a);
        }
        '''),
        _containsAllOf('void m(Object? a) => super.noSuchMethod('),
      );
    },
  );

  test(
    'widens the type of covariant parameters, overriding a mixin, to be nullable',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
        mixin FooMixin {
          void m(num a);
        }
        abstract class Foo with FooMixin {
          void m(covariant int a);
        }
        '''),
        _containsAllOf('void m(num? a) => super.noSuchMethod('),
      );
    },
  );

  test(
    "widens the type of covariant parameters, which don't have corresponding "
    'parameters in all overridden methods, to be nullable',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
        abstract class FooBaseBase {
          void m();
        }
        abstract class FooBase extends FooBaseBase {
          void m([num a]);
        }
        abstract class Foo extends FooBase {
          void m([covariant int a]);
        }
        '''),
        _containsAllOf('void m([num? a]) => super.noSuchMethod('),
      );
    },
  );

  test(
    'widens the type of covariant named parameters to be nullable',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
        abstract class FooBase extends FooBaseBase {
          void m({required num a});
        }
        abstract class Foo extends FooBase {
          void m({required covariant int a});
        }
        '''),
        _containsAllOf('void m({required num? a}) => super.noSuchMethod('),
      );
    },
  );

  test(
    'widens the type of covariant generic parameters to be nullable',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
        abstract class FooBase<T extends Object> {
          void m(Object a);
        }
        abstract class Foo<T extends Object> extends FooBase<T> {
          void m(covariant T a);
        }
        '''),
        _containsAllOf('void m(Object? a) => super.noSuchMethod('),
      );
    },
  );

  test('matches nullability of type arguments of a parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          void m(List<int?> a, List<int> b);
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m(
          List<int?>? a,
          List<int>? b,
        ) =>
        '''),
      ),
    );
  });

  test('matches nullability of return type of a generic function-typed '
      'parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          void m(int? Function() a, int Function() b);
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m(
          int? Function()? a,
          int Function()? b,
        ) =>
        '''),
      ),
    );
  });

  test(
    'matches nullability of return type of FutureOr<T> for potentially nullable T',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
        import 'dart:async';
        abstract class Foo {
          FutureOr<R> m<R>();
        }
        '''),
        _containsAllOf('_i2.FutureOr<R> m<R>() => (super.noSuchMethod('),
      );
    },
  );

  test('matches nullability of parameter types within a generic function-typed '
      'parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          void m(void Function(int?) a, void Function(int) b);
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m(
          void Function(int?)? a,
          void Function(int)? b,
        ) =>
        '''),
      ),
    );
  });

  test(
    'matches nullability of return type of a function-typed parameter',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
        abstract class Foo {
          void m(int? a(), int b());
        }
        '''),
        _containsAllOf(
          dedent2('''
        void m(
          int? Function()? a,
          int Function()? b,
        ) =>
        '''),
        ),
      );
    },
  );

  test('matches nullability of parameter types within a function-typed '
      'parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          void m(void a(int? x), void b(int x));
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m(
          void Function(int?)? a,
          void Function(int)? b,
        ) =>
        '''),
      ),
    );
  });

  test('matches requiredness of parameter types within a function-typed '
      'parameter', () async {
    await expectSingleNonNullableOutput(
      dedent('''
      class Foo {
        void m(void Function({required int p}) cb) {}
      }
      '''),
      _containsAllOf(
        'void m(void Function({required int p})? cb) => super.noSuchMethod(',
      ),
    );
  });

  test('matches nullability of a generic parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          void m<T>(T? a, T b);
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m<T>(
          T? a,
          T? b,
        ) =>
        '''),
      ),
    );
  });

  test('matches nullability of a dynamic parameter', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          void m(dynamic a, int b);
        }
        '''),
      _containsAllOf(
        dedent2('''
        void m(
          dynamic a,
          int? b,
        ) =>
        '''),
      ),
    );
  });

  test('matches nullability of non-nullable return type', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          int m(int a);
        }
        '''),
      _containsAllOf('int m(int? a) =>'),
    );
  });

  test('matches nullability of nullable return type', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          int? m(int a);
        }
        '''),
      _containsAllOf('int? m(int? a) =>'),
    );
  });

  test('matches nullability of return type type arguments', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          List<int?> m(int a);
        }
        '''),
      _containsAllOf('List<int?> m(int? a) =>'),
    );
  });

  test('matches nullability of nullable type variable return type', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          T? m<T>(int a);
        }
        '''),
      _containsAllOf('T? m<T>(int? a) =>'),
    );
  });

  test('overrides implicit return type with dynamic', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          m(int a);
        }
        '''),
      _containsAllOf(
        'dynamic m(int? a) => super.noSuchMethod(Invocation.method(',
      ),
    );
  });

  test('overrides abstract methods', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      abstract class Foo {
        dynamic f(int a);
      }
      '''),
      _containsAllOf(
        'dynamic f(int? a) => super.noSuchMethod(Invocation.method(',
      ),
    );
  });

  test('does not override methods with all nullable parameters', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo {
        int? method1(int? p) => null;
      }
      '''),
    );
    expect(mocksContent, isNot(contains('method1')));
  });

  test(
    'does not override methods with all nullable parameters (dynamic)',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      class Foo {
        int? method1(dynamic p) => null;
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test(
    'does not override methods with all nullable parameters (var untyped)',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      class Foo {
        int? method1(var p) => null;
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test(
    'does not override methods with all nullable parameters (final untyped)',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      class Foo {
        int? method1(final p) => null;
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test(
    'does not override methods with all nullable parameters (type variable)',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      class Foo<T> {
        int? method1(T? p) => null;
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test(
    'does not override methods with all nullable parameters (function-typed)',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      class Foo {
        int? method1(int Function()? p) => null;
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test(
    'does not override methods with an implicit dynamic return type',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      abstract class Foo {
        method1();
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test(
    'does not override methods with an explicit dynamic return type',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      abstract class Foo {
        dynamic method1();
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test('does not override methods with a nullable return type', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      abstract class Foo {
        int? method1();
      }
      '''),
    );
    expect(mocksContent, isNot(contains('method1')));
  });

  test(
    'does not override methods with a nullable return type (type variable)',
    () async {
      final mocksContent = await buildWithSingleNonNullableSource(
        dedent(r'''
      abstract class Foo<T> {
        T? method1();
      }
      '''),
      );
      expect(mocksContent, isNot(contains('method1')));
    },
  );

  test('overrides methods with a non-nullable return type', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
        abstract class Foo {
          int m();
        }
        '''),
      _containsAllOf(
        dedent2('''
        int m() => (super.noSuchMethod(
              Invocation.method(
                #m,
                [],
              ),
              returnValue: 0,
            ) as int);
        '''),
      ),
    );
  });

  test('overrides inherited methods with a non-nullable return type', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        class FooBase {
          num m() => 7;
        }
        class Foo extends FooBase {
          int m() => 7;
        }
        '''),
    );
    expect(mocksContent, contains('int m()'));
    expect(mocksContent, isNot(contains('num m()')));
  });

  test('overrides methods with a potentially non-nullable parameter', () async {
    await testWithNonNullable(
      {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {
          void m(T a) {}
        }
        '''),
      },
      outputs: {
        'foo|test/foo_test.mocks.dart': _containsAllOf(
          dedent2('''
          void m(T? a) => super.noSuchMethod(
                Invocation.method(
                  #m,
                  [a],
                ),
          '''),
        ),
      },
    );
  });

  test('overrides generic methods', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
        class Foo {
          dynamic f<T>(int a) {}
          dynamic g<T extends Foo>(int a) {}
        }
        '''),
    );
    expect(mocksContent, contains('dynamic f<T>(int? a) =>'));
    expect(mocksContent, contains('dynamic g<T extends _i2.Foo>(int? a) =>'));
  });

  test('overrides non-nullable instance getters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        int get m => 7;
      }
      '''),
      _containsAllOf(
        dedent2('''
        int get m => (super.noSuchMethod(
              Invocation.getter(#m),
              returnValue: 0,
            ) as int);
        '''),
      ),
    );
  });

  test('does not override nullable instance getters', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo {
        int? get getter1 => 7;
      }
      '''),
    );
    expect(mocksContent, isNot(contains('getter1')));
  });

  test('overrides inherited non-nullable instance getters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class FooBase {
        int get m => 7;
      }
      class Foo extends FooBase {}
      '''),
      _containsAllOf(
        dedent2('''
        int get m => (super.noSuchMethod(
              Invocation.getter(#m),
              returnValue: 0,
            ) as int);
        '''),
      ),
    );
  });

  test('overrides inherited instance getters only once', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent('''
      class FooBase {
        num get m => 7;
      }
      class Foo extends FooBase {
        int get m => 7;
      }
      '''),
    );
    expect(mocksContent, contains('int get m'));
    expect(mocksContent, isNot(contains('num get m')));
  });

  test('overrides non-nullable instance setters', () async {
    await expectSingleNonNullableOutput(
      dedent('''
      class Foo {
        void set m(int a) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        set m(int? a) => super.noSuchMethod(
              Invocation.setter(
                #m,
                a,
              ),
              returnValueForMissingStub: null,
            );
        '''),
      ),
    );
  });

  test('overrides nullable instance setters', () async {
    await expectSingleNonNullableOutput(
      dedent('''
      class Foo {
        void set m(int? a) {}
      }
      '''),
      _containsAllOf(
        dedent2('''
        set m(int? a) => super.noSuchMethod(
              Invocation.setter(
                #m,
                a,
              ),
              returnValueForMissingStub: null,
            );
        '''),
      ),
    );
  });

  test(
    'overrides nullable instance setters with wildcard parameters',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
      class Foo {
        void set m(int? _) {}
      }
      '''),
        _containsAllOf(
          dedent2('''
        set m(int? _value) => super.noSuchMethod(
              Invocation.setter(#m, _value),
              returnValueForMissingStub: null,
            );
        '''),
        ),
      );
    },
  );

  test('overrides inherited non-nullable instance setters', () async {
    await expectSingleNonNullableOutput(
      dedent('''
      class FooBase {
        void set m(int a) {}
      }
      class Foo extends FooBase {}
      '''),
      _containsAllOf(
        dedent2('''
        set m(int? a) => super.noSuchMethod(
              Invocation.setter(
                #m,
                a,
              ),
              returnValueForMissingStub: null,
            );
        '''),
      ),
    );
  });

  test('overrides inherited non-nullable instance setters only once', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent('''
      class FooBase {
        set m(int a) {}
      }
      class Foo extends FooBase {
        set m(num a) {}
      }
      '''),
    );
    expect(mocksContent, contains('set m(num? a)'));
    expect(mocksContent, isNot(contains('set m(int? a)')));
  });

  test('overrides non-nullable fields', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        int m;
      }
      '''),
      _containsAllOf(
        dedent2('''
        int get m => (super.noSuchMethod(
              Invocation.getter(#m),
              returnValue: 0,
            ) as int);
      '''),
        dedent2('''
        set m(int? value) => super.noSuchMethod(
              Invocation.setter(
                #m,
                value,
              ),
              returnValueForMissingStub: null,
            );
        '''),
      ),
    );
  });

  test('overrides inherited non-nullable fields', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class FooBase {
        int m;
      }
      class Foo extends FooBase {}
      '''),
      _containsAllOf(
        dedent2('''
        int get m => (super.noSuchMethod(
              Invocation.getter(#m),
              returnValue: 0,
            ) as int);
        '''),
        dedent2('''
        set m(int? value) => super.noSuchMethod(
              Invocation.setter(
                #m,
                value,
              ),
              returnValueForMissingStub: null,
            );
        '''),
      ),
    );
  });

  test('overrides inherited non-nullable fields only once', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent('''
      class FooBase {
        num m;
      }
      class Foo extends FooBase<int> {
        int get m => 7;
        void set m(covariant int value) {}
      }
      '''),
    );
    expect(mocksContent, contains('int get m'));
    expect(mocksContent, contains('set m(int? value)'));
    expect(mocksContent, isNot(contains('num get m')));
    expect(mocksContent, isNot(contains('set m(num? value)')));
  });

  test('overrides final non-nullable fields', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        final int m;
        Foo(this.m);
      }
      '''),
      _containsAllOf(
        dedent2('''
        int get m => (super.noSuchMethod(
              Invocation.getter(#m),
              returnValue: 0,
            ) as int);
      '''),
      ),
    );
  });

  test('does not override getters for nullable fields', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo {
        int? field1;
      }
      '''),
    );
    expect(mocksContent, isNot(contains('get field1')));
  });

  test('does not override private fields', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo {
        int _field1;
      }
      '''),
    );
    expect(mocksContent, isNot(contains('int _field1')));
  });

  test('does not override static fields', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo {
        static int field1;
      }
      '''),
    );
    expect(mocksContent, isNot(contains('int field1')));
  });

  test('overrides binary operators', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        int operator +(Foo other) => 7;
      }
      '''),
      _containsAllOf(
        dedent2('''
        int operator +(_i2.Foo? other) => (super.noSuchMethod(
              Invocation.method(
                #+,
                [other],
              ),
              returnValue: 0,
            ) as int);
      '''),
      ),
    );
  });

  test('overrides index operators', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        int operator [](int x) => 7;
      }
      '''),
      _containsAllOf(
        dedent2('''
        int operator [](int? x) => (super.noSuchMethod(
              Invocation.method(
                #[],
                [x],
              ),
              returnValue: 0,
            ) as int);
      '''),
      ),
    );
  });

  test('overrides unary operators', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        int operator ~() => 7;
      }
      '''),
      _containsAllOf(
        dedent2('''
        int operator ~() => (super.noSuchMethod(
              Invocation.method(
                #~,
                [],
              ),
              returnValue: 0,
            ) as int);
      '''),
      ),
    );
  });

  test('creates dummy non-null bool return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        bool m() => false;
      }
      '''),
      _containsAllOf('returnValue: false'),
    );
  });

  test('creates dummy non-null double return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        double m() => 3.14;
      }
      '''),
      _containsAllOf('returnValue: 0.0'),
    );
  });

  test('creates dummy non-null int return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        int m() => 7;
      }
      '''),
      _containsAllOf('returnValue: 0'),
    );
  });

  test(
    'calls dummyValue to get a dummy non-null String return value',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        String m() => "Hello";
      }
      '''),
        _containsAllOf('returnValue: _i3.dummyValue<String>('),
      );
    },
  );

  test('creates dummy non-null List return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        List<Foo> m() => [Foo()];
      }
      '''),
      _containsAllOf('returnValue: <_i2.Foo>[]'),
    );
  });

  test('creates dummy non-null Set return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Set<Foo> m() => {Foo()};
      }
      '''),
      _containsAllOf('returnValue: <_i2.Foo>{}'),
    );
  });

  test('creates dummy non-null Map return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Map<int, Foo> m() => {7: Foo()};
      }
      '''),
      _containsAllOf('returnValue: <int, _i2.Foo>{}'),
    );
  });

  test('creates dummy non-null raw-typed return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      abstract class Foo {
        Map m();
      }
      '''),
      _containsAllOf('returnValue: <dynamic, dynamic>{}'),
    );
  });

  test('creates dummy non-null return values for Futures', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Future<bool> m() async => false;
      }
      '''),
      _containsAllOf('returnValue: _i3.Future<bool>.value(false)'),
    );
  });

  test(
    'creates dummy non-null return values for Futures of unknown types',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        Future<T> m<T>() async => false;
      }
      '''),
        _containsAllOf('dummyValueOrNull<T>(', '_FakeFuture_0<T>('),
      );
    },
  );

  test('creates dummy non-null Stream return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      abstract class Foo {
        Stream<int> m();
      }
      '''),
      _containsAllOf('returnValue: _i3.Stream<int>.empty()'),
    );
  });

  test('creates dummy non-null return values for unknown classes', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Bar m() => Bar('name');
      }
      class Bar {
        final String name;
        Bar(this.name);
      }
      '''),
      _containsAllOf('''
        returnValue: _FakeBar_0(
          this,
          Invocation.method(
            #m,
            [],
          ),
        )'''),
    );
  });

  test('creates dummy non-null return values for generic type', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      abstract class Foo {
        Bar<int> m();
      }
      class Bar<T> {}
      '''),
      _containsAllOf('''
        returnValue: _FakeBar_0<int>(
          this,
          Invocation.method(
            #m,
            [],
          ),
        )'''),
    );
  });

  test('creates dummy non-null return values for enums', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Bar m1() => Bar('name');
      }
      enum Bar {
        one,
        two,
      }
      '''),
      _containsAllOf('returnValue: _i2.Bar.one'),
    );
  });

  test('creates a dummy non-null function-typed return value, with optional '
      'parameters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void Function(int, [String]) m() => (int i, [String s]) {};
      }
      '''),
      _containsAllOf('''
        returnValue: (
          int __p0, [
          String? __p1,
        ]) {}'''),
    );
  });

  test('creates a dummy non-null function-typed return value, with named '
      'parameters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        void Function(Foo, {bool b}) m() => (Foo f, {bool b}) {};
      }
      '''),
      _containsAllOf('''
        returnValue: (
          _i2.Foo __p0, {
          bool? b,
        }) {}'''),
    );
  });

  test('creates a dummy non-null function-typed return value, with required '
      'named parameters', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      abstract class Foo {
        void Function(Foo, {required bool b}) m();
      }
      '''),
      _containsAllOf('''
        returnValue: (
          _i2.Foo __p0, {
          required bool b,
        }) {}'''),
    );
  });

  test('creates a dummy non-null function-typed return value, with non-core '
      'return type', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Foo Function() m() => () => Foo();
      }
      '''),
      _containsAllOf('''
        returnValue: () => _FakeFoo_0(
          this,
          Invocation.method(
            #m,
            [],
          ),
        )'''),
    );
  });

  test(
    'creates a dummy non-null function-typed return value, with private type '
    'alias',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      typedef _Callback = Foo Function();
      class Foo {
        _Callback m() => () => Foo();
      }
      '''),
        _containsAllOf('''
        returnValue: () => _FakeFoo_0(
          this,
          Invocation.method(
            #m,
            [],
          ),
        )
      '''),
      );
    },
  );

  test(
    'creates a dummy non-null generic function-typed return value',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Foo {
        T? Function<T>(T) m() => (int i, [String s]) {};
      }
      '''),
        _containsAllOf('returnValue: <T>(T __p0) => null'),
      );
    },
  );

  test(
    'creates a dummy non-null generic bounded function-typed return value',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      import 'dart:io';
      class Foo {
        T? Function<T extends File>(T) m() => (int i, [String s]) {};
      }
      '''),
        _containsAllOf(
          dedent2('''
      T? Function<T extends _i3.File>(T) m() => (super.noSuchMethod(
            Invocation.method(
              #m,
              [],
            ),
            returnValue: <T extends _i3.File>(T __p0) => null,
          ) as T? Function<T extends _i3.File>(T));
      '''),
        ),
      );
    },
  );

  test('creates a dummy non-null function-typed (with an imported parameter '
      'type) return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      import 'dart:io';
      class Foo {
        void Function(File) m() => (int i, [String s]) {};
      }
      '''),
      _containsAllOf(
        dedent2('''
      void Function(_i3.File) m() => (super.noSuchMethod(
            Invocation.method(
              #m,
              [],
            ),
            returnValue: (_i3.File __p0) {},
          ) as void Function(_i3.File));
      '''),
      ),
    );
  });

  test('creates a dummy non-null function-typed (with an imported return type) '
      'return value', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      import 'dart:io';
      class Foo {
        File Function() m() => (int i, [String s]) {};
      }
      '''),
      _containsAllOf(
        dedent2('''
      _i2.File Function() m() => (super.noSuchMethod(
            Invocation.method(
              #m,
              [],
            ),
            returnValue: () => _FakeFile_0(
              this,
              Invocation.method(
                #m,
                [],
              ),
            ),
          ) as _i2.File Function());
      '''),
      ),
    );
  });

  test('generates a fake class used in return values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Bar m1() => Bar('name1');
      }
      class Bar {}
      '''),
      _containsAllOf(
        dedent('''
      class _FakeBar_0 extends _i1.SmartFake implements _i2.Bar {
        _FakeBar_0(
          Object parent,
          Invocation parentInvocation,
        ) : super(
                parent,
                parentInvocation,
              );
      }'''),
      ),
    );
  });

  test('generates fake classes with unique names', () async {
    final mocksOutput = await buildWithNonNullable({
      ...annotationsAsset,
      ...simpleTestAsset,
      'foo|lib/foo.dart': '''
        import 'bar1.dart' as one;
        import 'bar2.dart' as two;
        abstract class Foo {
          one.Bar m1();
          two.Bar m2();
        }
        ''',
      'foo|lib/bar1.dart': '''
        class Bar {}
        ''',
      'foo|lib/bar2.dart': '''
        class Bar {}
        ''',
    });
    expect(
      mocksOutput,
      contains('class _FakeBar_0 extends _i1.SmartFake implements _i2.Bar {'),
    );
    expect(
      mocksOutput,
      contains('class _FakeBar_1 extends _i1.SmartFake implements _i3.Bar {'),
    );
  });

  test('generates a fake generic class used in return values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Bar m1() => Bar();
      }
      class Bar<T, U> {}
      '''),
      _containsAllOf(
        'class _FakeBar_0<T, U> extends _i1.SmartFake implements _i2.Bar<T, U> {',
      ),
    );
  });

  test(
    'generates a fake, bounded generic class used in return values',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Baz {}
      class Bar<T extends Baz> {}
      class Foo {
        Bar<Baz> m1() => Bar();
      }
      '''),
        _containsAllOf(
          dedent('''
      class _FakeBar_0<T extends _i1.Baz> extends _i2.SmartFake
          implements _i1.Bar<T> {
      '''),
        ),
      );
    },
  );

  test('generates a fake, aliased class used in return values', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Baz {}
      class Bar<T extends Baz> {}
      typedef BarOfBaz = Bar<Baz>;
      class Foo {
        BarOfBaz m1() => Bar();
      }
      '''),
      _containsAllOf(
        dedent('''
      class _FakeBar_0<T extends _i1.Baz> extends _i2.SmartFake
          implements _i1.Bar<T> {
      '''),
      ),
    );
  });

  test(
    'generates a fake, recursively bounded generic class used in return values',
    () async {
      await expectSingleNonNullableOutput(
        dedent(r'''
      class Baz<T extends Baz<T>> {}
      class Bar<T> {}
      class Foo {
        Bar<Baz> m1() => Bar();
      }
      '''),
        _containsAllOf(
          'class _FakeBar_0<T> extends _i1.SmartFake implements _i2.Bar<T> {',
        ),
      );
    },
  );

  test(
    'generates a fake class with an overridden `toString` implementation',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
      class Foo {
        Bar m1() => Bar('name1');
      }
      class Bar {
        String toString({bool a = true}) => '';
      }
      '''),
        _containsAllOf(
          dedent('''
      class _FakeBar_0 extends _i1.SmartFake implements _i2.Bar {
        _FakeBar_0(
          Object parent,
          Invocation parentInvocation,
        ) : super(
                parent,
                parentInvocation,
              );

        @override
        String toString({bool? a = true}) => super.toString();
      }
      '''),
        ),
      );
    },
  );

  test('imports libraries for types used in generated fake classes', () async {
    await expectSingleNonNullableOutput(
      dedent('''
      class Foo {
        Bar m1() => Bar('name1');
      }
      class Bar {
        String toString({Baz? baz}) => '';
      }
      class Baz {}
      '''),
      _containsAllOf('String toString({_i2.Baz? baz}) => super.toString();'),
    );
  });

  test('deduplicates fake classes', () async {
    final mocksContent = await buildWithSingleNonNullableSource(
      dedent(r'''
      class Foo {
        Bar m1() => Bar('name1');
        Bar m2() => Bar('name2');
      }
      class Bar {
        final String name;
        Bar(this.name);
      }
      '''),
    );
    final mocksContentLines = mocksContent.split('\n');
    // The _FakeBar_0 class should be generated exactly once.
    expect(
      mocksContentLines.where((line) => line.contains('class _FakeBar_0')),
      hasLength(1),
    );
  });

  test('does not try to generate a fake for a final class', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Bar m1() => Bar();
      }
      final class Bar {}
      '''),
      _containsAllOf('dummyValue<_i2.Bar>('),
    );
  });

  test('does not try to generate a fake for a base class', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Bar m1() => Bar();
      }
      base class Bar {}
      '''),
      _containsAllOf('dummyValue<_i2.Bar>('),
    );
  });

  test('does not try to generate a fake for a sealed class', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      class Foo {
        Bar m1() => Bar();
      }
      sealed class Bar {}
      '''),
      _containsAllOf('dummyValue<_i2.Bar>('),
    );
  });

  test('throws when GenerateMocks is given a class multiple times', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([Foo, Foo])
        void main() {}
        ''',
      },
      message: contains(
        'Mockito cannot generate two mocks with the same name: MockFoo (for '
        'Foo declared in /foo/lib/foo.dart, and for Foo declared in '
        '/foo/lib/foo.dart)',
      ),
    );
  });

  test(
    'throws when GenerateMocks is given a class with a getter with a private '
    'return type',
    () async {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          ...simpleTestAsset,
          'foo|lib/foo.dart': dedent('''
        abstract class Foo with FooMixin {}
        mixin FooMixin {
          _Bar get f => _Bar();
        }
        class _Bar {}
        '''),
        },
        message: contains(
          "The property accessor 'FooMixin.f' features a private return type, "
          'and cannot be stubbed.',
        ),
      );
    },
  );

  test(
    'throws when GenerateMocks is given a class with a setter with a private '
    'return type',
    () async {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          ...simpleTestAsset,
          'foo|lib/foo.dart': dedent('''
        abstract class Foo with FooMixin {}
        mixin FooMixin {
          void set f(_Bar value) {}
        }
        class _Bar {}
        '''),
        },
        message: contains(
          "The property accessor 'FooMixin.f' features a private parameter "
          "type, '_Bar', and cannot be stubbed.",
        ),
      );
    },
  );

  test('throws when GenerateMocks is given a class with a method with a '
      'private return type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          _Bar m(int a);
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private return type, and cannot be "
        'stubbed.',
      ),
    );
  });

  test('throws when GenerateMocks is given a class with an inherited method '
      'with a private return type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo with FooMixin {}
        mixin FooMixin {
          _Bar m(int a);
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'FooMixin.m' features a private return type, and cannot "
        'be stubbed.',
      ),
    );
  });

  test('throws when GenerateMocks is given a class with a method with a '
      'type alias return type which refers to private types', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          Callback m(int a);
        }
        class _Bar {}
        typedef Callback = Function(_Bar?);
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private parameter type, '_Bar', and "
        'cannot be stubbed.',
      ),
    );
  });

  test(
    'throws when GenerateMocks is given a class with a method with a '
    'private type alias parameter type which refers to private types',
    () async {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          ...simpleTestAsset,
          'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          void m(_Callback c);
        }
        class _Bar {}
        typedef _Callback = Function(_Bar?);
        '''),
        },
        message: contains(
          "The method 'Foo.m' features a private parameter type, '_Bar', and "
          'cannot be stubbed.',
        ),
      );
    },
  );

  test('throws when GenerateMocks is given a class with a method with a return '
      'type with private type arguments', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          List<_Bar> m(int a);
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private type argument, and cannot be "
        'stubbed.',
      ),
    );
  });

  test('throws when GenerateMocks is given a class with a method with a return '
      'function type, with a private return type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          _Bar Function() m();
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private return type, "
        'and cannot be stubbed.',
      ),
    );
  });

  test('throws when GenerateMocks is given a class with a method with a '
      'private parameter type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {
          void m(_Bar a) {}
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private parameter type, '_Bar', and "
        'cannot be stubbed.',
      ),
    );
  });

  test('throws when GenerateMocks is given a class with a method with a '
      'parameter with private type arguments', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {
          void m(List<_Bar> a) {}
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private type argument, and cannot be "
        'stubbed.',
      ),
    );
  });

  test('throws when GenerateMocks is given a class with a method with a '
      'function parameter type, with a private return type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {
          void m(_Bar Function() a) {}
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private return type, and cannot be "
        'stubbed.',
      ),
    );
  });

  test('throws when GenerateMocks is given a class with a method with a return '
      'function type, with a private parameter type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          Function(_Bar) m();
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private parameter type, '_Bar', and "
        'cannot be stubbed.',
      ),
    );
  });

  test(
    'throws when GenerateMocks is given a class with a type parameter with a '
    'private bound',
    () async {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          ...simpleTestAsset,
          'foo|lib/foo.dart': dedent(r'''
        class Foo<T extends _Bar> {
          void m(int a) {}
        }
        class _Bar {}
        '''),
        },
        message: contains(
          "The class 'Foo' features a private type parameter bound, and cannot "
          'be stubbed.',
        ),
      );
    },
  );

  test('throws when GenerateMocks is given a class with a method with a '
      'type parameter with a private bound', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {
          void m<T extends _Bar>(int a) {}
        }
        class _Bar {}
        '''),
      },
      message: contains(
        "The method 'Foo.m' features a private type parameter bound, and "
        'cannot be stubbed.',
      ),
    );
  });

  test("calls 'dummyValue' for a getter with a "
      'non-nullable class-declared type variable type', () async {
    await expectSingleNonNullableOutput(
      dedent('''
        abstract class Foo<T> {
          T get f;
        }
        '''),
      _containsAllOf('dummyValue<T>('),
    );
  });

  test("calls 'dummyValue' for a method with a "
      'non-nullable class-declared type variable return type', () async {
    await expectSingleNonNullableOutput(
      dedent('''
        abstract class Foo<T> {
          T m(int a);
        }
        '''),
      _containsAllOf('dummyValue<T>('),
    );
  });

  test("calls 'dummyValue' for a method with a "
      'non-nullable method-declared type variable return type', () async {
    await expectSingleNonNullableOutput(
      dedent('''
        abstract class Foo {
          T m<T>(int a);
        }
        '''),
      _containsAllOf('dummyValue<T>('),
    );
  });

  test(
    "calls 'dummyValue' for a method with a "
    'non-nullable method-declared bounded type variable return type',
    () async {
      await expectSingleNonNullableOutput(
        dedent('''
        abstract class Foo {
          T m<T extends num>(int a);
        }
        '''),
        _containsAllOf('dummyValue<T>('),
      );
    },
  );

  test('throws when GenerateMocks is missing an argument', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        // Missing required argument to GenerateMocks.
        @GenerateMocks()
        void main() {}
        '''),
      },
      message: contains('The GenerateMocks "classes" argument is missing'),
    );
  });

  test('throws when GenerateMocks is given a private class', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        @GenerateMocks([_Foo])
        void main() {}
        class _Foo {}
        '''),
      },
      message: contains("Mockito cannot mock a private type: '_Foo'."),
    );
  });

  test('throws when GenerateMocks references an unresolved type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        '''),
        'foo|test/foo_test.dart': dedent('''
        // missing foo.dart import.
        import 'package:mockito/annotations.dart';
        @GenerateMocks([List, Foo])
        void main() {}
        '''),
      },
      message: contains('includes an unknown type'),
    );
  });

  test(
    'throws when two distinct classes with the same name are mocked',
    () async {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          'foo|lib/a.dart': dedent(r'''
        class Foo {}
        '''),
          'foo|lib/b.dart': dedent(r'''
        class Foo {}
        '''),
          'foo|test/foo_test.dart': dedent('''
        import 'package:foo/a.dart' as a;
        import 'package:foo/b.dart' as b;
        import 'package:mockito/annotations.dart';
        @GenerateMocks([a.Foo, b.Foo])
        void main() {}
        '''),
        },
        message: contains(
          'Mockito cannot generate two mocks with the same name: MockFoo (for '
          'Foo declared in /foo/lib/a.dart, and for Foo declared in '
          '/foo/lib/b.dart)',
        ),
      );
    },
  );

  test('throws when a mock class of the same name already exists', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        '''),
        'foo|test/foo_test.dart': dedent('''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([Foo])
        void main() {}
        class MockFoo {}
        '''),
      },
      message: contains(
        'Mockito cannot generate a mock with a name which conflicts with '
        'another class declared in this library: MockFoo',
      ),
    );
  });

  test('throws when a mock class of class-to-mock already exists', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...mockitoAssets,
        'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        '''),
        'foo|test/foo_test.dart': dedent('''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        import 'package:mockito/mockito.dart';
        @GenerateMocks([Foo])
        void main() {}
        class FakeFoo extends Mock implements Foo {}
        '''),
      },
      message: contains(
        'contains a class which appears to already be mocked inline: FakeFoo',
      ),
    );
  });

  test('throws when GenerateMocks references a non-type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        @GenerateMocks([7])
        void main() {}
        '''),
      },
      message: 'The "classes" argument includes a non-type: int (7)',
    );
  });

  test('throws when GenerateMocks references a function typedef', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        typedef Foo = void Function();
        '''),
      },
      message: 'Mockito cannot mock a non-class: Foo',
    );
  });

  test('throws when GenerateMocks references an enum', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        enum Foo {}
        '''),
      },
      message: "Mockito cannot mock an enum: 'Foo'",
    );
  });

  test('throws when GenerateMocks references an extension', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        extension Foo on String {}
        '''),
      },
      message: contains('includes an extension'),
    );
  });

  test('throws when GenerateMocks references a non-subtypeable type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        @GenerateMocks([int])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a non-subtypable type: 'int'"),
    );
  });

  test('throws when GenerateMocks references a sealed class', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        sealed class Foo {}
        @GenerateMocks([Foo])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a sealed class 'Foo'"),
    );
  });

  test(
    'throws when GenerateMocks references sealed a class via typedef',
    () async {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        sealed class Foo {}
        typedef Bar = Foo;
        @GenerateMocks([Bar])
        void main() {}
        '''),
        },
        message: contains("Mockito cannot mock a sealed class 'Foo'"),
      );
    },
  );

  test('throws when GenerateMocks references a base class', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        base class Foo {}
        @GenerateMocks([Foo])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a base class 'Foo'"),
    );
  });

  test('throws when GenerateMocks references a final class', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        final class Foo {}
        @GenerateMocks([Foo])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a final class 'Foo'"),
    );
  });

  test('adds ignore: must_be_immutable analyzer comment if mocked class is '
      'immutable', () async {
    await expectSingleNonNullableOutput(
      dedent(r'''
      import 'package:meta/meta.dart';
      @immutable
      class Foo {
        void foo();
      }
      '''),
      _containsAllOf('// ignore: must_be_immutable\nclass MockFoo'),
    );
  });

  group('typedef mocks', () {
    group('are generated properly', () {
      test('when aliased type parameters are instantiated', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<T> {}
            typedef Bar = Foo<int>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Bar])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar'));
      });

      test('when no aliased type parameters are instantiated', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<T> {}
            typedef Bar = Foo;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Bar])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar'));
      });

      test('when the aliased type has no type parameters', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo {}
            typedef Bar = Foo;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Bar])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar'));
      });

      test('when the typedef defines a type', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A, B> {}
            typedef Bar<X> = Foo<int, X>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Bar])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar<X> extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar<X>'));
      });

      test('when the typedef defines a bounded type', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A> {}
            typedef Bar<X extends num> = Foo<X>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Bar])
            void main() {}
          ''',
        });

        expect(
          mocksContent,
          contains('class MockBar<X extends num> extends _i1.Mock'),
        );
        expect(mocksContent, contains('implements _i2.Bar<X>'));
      });

      test('when the aliased type is a mixin', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            mixin Foo {
              String get value;
            }

            typedef Bar = Foo;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateMocks([Bar])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar'));
        expect(mocksContent, contains('String get value'));
      });

      test('when the aliased type is another typedef', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo {}

            typedef Bar = Foo;
            typedef Baz = Bar;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateMocks([Baz])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBaz extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Baz'));
      });

      test('when it\'s a function which returns any type', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Bar {}
            typedef CreateBar = Bar Function();
            class BaseFoo<T> {
              BaseFoo(this.t);
              final T t;
            }
            class Foo extends BaseFoo<CreateBar> {
              Foo() : super(() => 1);
            }
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Foo])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockFoo extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Foo'));
      });
      test(
        'when the underlying type is identical to another type alias',
        () async {
          final mocksContent = await buildWithNonNullable({
            ...annotationsAsset,
            'foo|lib/foo.dart': dedent(r'''
            class Bar {}
            typedef BarDef = int Function();
            typedef BarDef2 = int Function();
            class BaseFoo<T, P> {
              BaseFoo(this.t1, this.t2);
              final T t1;
              final P t2;
            }
            class Foo extends BaseFoo<BarDef, BarDef2> {
              Foo() : super(() => 1, () => 2);
            }
          '''),
            'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Foo])
            void main() {}
          ''',
          });

          expect(mocksContent, contains('class MockFoo extends _i1.Mock'));
          expect(mocksContent, contains('implements _i2.Foo'));
          expect(mocksContent, contains('_i2.BarDef get t1'));
          expect(mocksContent, contains('_i2.BarDef2 get t2'));
        },
      );
    });

    test('generation throws when the aliased type is nullable', () {
      _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
          class Foo {
            T get value;
          }

          typedef Bar = Foo?;
        '''),
          'foo|test/foo_test.dart': '''
          import 'package:foo/foo.dart';
          import 'package:mockito/annotations.dart';

          @GenerateMocks([Bar])
          void main() {}
        ''',
        },
        message: contains(
          'Mockito cannot mock a type-aliased nullable type: Bar',
        ),
        enabledExperiments: ['nonfunction-type-aliases'],
        languageVersion: LanguageVersion(2, 13),
      );
    });
  });
  test('Void in argument type gets overriden to dynamic', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
      class Foo {
        void m(void x) {}
      }
      '''),
      'foo|test/foo_test.dart': dedent(r'''
      import 'package:foo/foo.dart';
      import 'package:mockito/annotations.dart';

      @GenerateMocks([Foo])
      void main() {}
      '''),
    });
    expect(mocksContent, contains('void m(dynamic x)'));
  });
  group('Record types', () {
    test('are supported as arguments', () async {
      await expectSingleNonNullableOutput(
        dedent('''
        abstract class Foo {
          int m((int, {Foo foo}) a);
        }
        '''),
        _containsAllOf('int m((int, {_i2.Foo foo})? a)'),
      );
    });
    test('are supported as return types', () async {
      await expectSingleNonNullableOutput(
        dedent('''
        class Bar {}
        abstract class Foo {
          Future<(int, {Bar bar})> get v;
        }
        '''),
        decodedMatches(
          allOf(
            contains('Future<(int, {_i2.Bar bar})> get v'),
            contains('returnValue: _i3.Future<(int, {_i2.Bar bar})>.value('),
            contains('bar: _FakeBar_0('),
          ),
        ),
      );
    });
    test('are supported as type arguments', () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
          class Bar {}
          class BaseFoo<T> {
            BaseFoo(this.t);
            final T t;
          }
          class Foo extends BaseFoo<(Bar, Bar)> {
            Foo() : super((Bar(), Bar()));
          }
          '''),
        'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Foo])
            void main() {}
          ''',
      });

      expect(mocksContent, contains('class MockFoo extends _i1.Mock'));
      expect(mocksContent, contains('implements _i2.Foo'));
    });
    test('are supported as nested type arguments', () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
            class Bar {}
            class BaseFoo<T> {
              BaseFoo(this.t);
              final T t;
            }
            class Foo extends BaseFoo<(int, (Bar, Bar))> {
              Foo() : super(((1, (Bar(), Bar()))));
            }
          '''),
        'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateMocks([Foo])
            void main() {}
          ''',
      });

      expect(mocksContent, contains('class MockFoo extends _i1.Mock'));
      expect(mocksContent, contains('implements _i2.Foo'));
    });
  });

  group('Extension types', () {
    test('are supported as arguments', () async {
      await expectSingleNonNullableOutput(
        dedent('''
        extension type E(int v) {}
        class Foo {
          int m(E e);
        }
        '''),
        _containsAllOf('int m(_i2.E? e)'),
      );
    });

    test('are supported as return types', () async {
      await expectSingleNonNullableOutput(
        dedent('''
        extension type E(int v) {}
        class Foo {
          E get v;
        }
        '''),
        decodedMatches(allOf(contains('E get v'), contains('returnValue: 0'))),
      );
    });
  });
  group('build_extensions support', () {
    test('should export mocks to different directory', () async {
      await testWithNonNullable(
        {
          ...annotationsAsset,
          ...simpleTestAsset,
          'foo|lib/foo.dart': '''
        import 'bar.dart';
        class Foo extends Bar {}
        ''',
          'foo|lib/bar.dart': '''
        import 'dart:async';
        class Bar {
          m(Future<void> a) {}
        }
        ''',
        },
        config: {
          'build_extensions': {'^test/{{}}.dart': 'test/mocks/{{}}.mocks.dart'},
        },
      );
      final mocksAsset = AssetId('foo', 'test/mocks/foo_test.mocks.dart');
      final mocksContent = utf8.decode(writer.assets[mocksAsset]!);
      expect(mocksContent, contains("import 'dart:async' as _i3;"));
      expect(mocksContent, contains('m(_i3.Future<void>? a)'));
    });

    test('should throw if it has confilicting outputs', () async {
      await expectLater(
        testWithNonNullable(
          {
            ...annotationsAsset,
            ...simpleTestAsset,
            'foo|lib/foo.dart': '''
        import 'bar.dart';
        class Foo extends Bar {}
        ''',
            'foo|lib/bar.dart': '''
        import 'dart:async';
        class Bar {
          m(Future<void> a) {}
        }
        ''',
          },
          config: {
            'build_extensions': {
              '^test/{{}}.dart': 'test/mocks/{{}}.mocks.dart',
              'test/{{}}.dart': 'test/{{}}.something.mocks.dart',
            },
          },
        ),
        throwsArgumentError,
      );
      final mocksAsset = AssetId('foo', 'test/mocks/foo_test.mocks.dart');
      final otherMocksAsset = AssetId('foo', 'test/mocks/foo_test.mocks.dart');
      final somethingMocksAsset = AssetId(
        'foo',
        'test/mocks/foo_test.something.mocks.dart',
      );

      expect(writer.assets.containsKey(mocksAsset), false);
      expect(writer.assets.containsKey(otherMocksAsset), false);
      expect(writer.assets.containsKey(somethingMocksAsset), false);
    });

    test('should throw if input is in incorrect format', () async {
      await expectLater(
        testWithNonNullable(
          {
            ...annotationsAsset,
            ...simpleTestAsset,
            'foo|lib/foo.dart': '''
        import 'bar.dart';
        class Foo extends Bar {}
        ''',
            'foo|lib/bar.dart': '''
        import 'dart:async';
        class Bar {
          m(Future<void> a) {}
        }
        ''',
          },
          config: {
            'build_extensions': {'^test/{{}}': 'test/mocks/{{}}.mocks.dart'},
          },
        ),
        throwsArgumentError,
      );
      final mocksAsset = AssetId('foo', 'test/mocks/foo_test.mocks.dart');
      final mocksAssetOriginal = AssetId('foo', 'test/foo_test.mocks.dart');

      expect(writer.assets.containsKey(mocksAsset), false);
      expect(writer.assets.containsKey(mocksAssetOriginal), false);
    });

    test('should throw if output is in incorrect format', () async {
      await expectLater(
        testWithNonNullable(
          {
            ...annotationsAsset,
            ...simpleTestAsset,
            'foo|lib/foo.dart': '''
        import 'bar.dart';
        class Foo extends Bar {}
        ''',
            'foo|lib/bar.dart': '''
        import 'dart:async';
        class Bar {
          m(Future<void> a) {}
        }
        ''',
          },
          config: {
            'build_extensions': {'^test/{{}}.dart': 'test/mocks/{{}}.g.dart'},
          },
        ),
        throwsArgumentError,
      );
      final mocksAsset = AssetId('foo', 'test/mocks/foo_test.mocks.dart');
      final mocksAssetOriginal = AssetId('foo', 'test/foo_test.mocks.dart');
      expect(writer.assets.containsKey(mocksAsset), false);
      expect(writer.assets.containsKey(mocksAssetOriginal), false);
    });
  });
}

TypeMatcher<List<int>> _containsAllOf(String a, [String? b]) => decodedMatches(
  b == null
      ? containsIgnoringFormatting(a)
      : allOf(containsIgnoringFormatting(a), containsIgnoringFormatting(b)),
);

/// Expect that [testBuilder], given [assets], in a package which has opted into
/// null safety, throws an [InvalidMockitoAnnotationException] with a message
/// containing [message].
void _expectBuilderThrows({
  required Map<String, String> assets,
  required dynamic /*String|Matcher<List<int>>*/ message,
  List<String> enabledExperiments = const [],
  LanguageVersion? languageVersion,
}) {
  final packageConfig = PackageConfig([
    Package(
      'foo',
      Uri.file('/foo/'),
      packageUriRoot: Uri.file('/foo/lib/'),
      languageVersion: languageVersion ?? LanguageVersion(2, 12),
    ),
  ]);

  expect(
    () => withEnabledExperiments(
      () => testBuilder(
        buildMocks(BuilderOptions({})),
        assets,
        packageConfig: packageConfig,
      ),
      enabledExperiments,
    ),
    throwsA(
      TypeMatcher<InvalidMockitoAnnotationException>().having(
        (e) => e.message,
        'message',
        message,
      ),
    ),
  );
}

/// Dedent [input], so that each line is shifted to the left, so that the first
/// line is at the 0 column.
String dedent(String input) {
  final indentMatch = RegExp(r'^(\s*)').firstMatch(input)!;
  final indent = ''.padRight(indentMatch.group(1)!.length);
  return input.splitMapJoin(
    '\n',
    onNonMatch: (s) => s.replaceFirst(RegExp('^$indent'), ''),
  );
}

/// Dedent [input], so that each line is shifted to the left, so that the first
/// line is at column 2 (starting position for a class member).
String dedent2(String input) {
  final indentMatch = RegExp(r'^  (\s*)').firstMatch(input)!;
  final indent = ''.padRight(indentMatch.group(1)!.length);
  return input
      .replaceFirst(RegExp(r'\s*$'), '')
      .splitMapJoin(
        '\n',
        onNonMatch: (s) => s.replaceFirst(RegExp('^$indent'), ''),
      );
}
