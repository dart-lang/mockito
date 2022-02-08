// Copyright 2020 Dart Mockito authors
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
import 'dart:convert' show utf8;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:mockito/src/builder.dart';
import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

Builder buildMocks(BuilderOptions options) => MockBuilder();

const annotationsAsset = {
  'mockito|lib/annotations.dart': '''
class GenerateMocks {
  final List<Type> classes;
  final List<MockSpec> customMocks;

  const GenerateMocks(this.classes, {this.customMocks = []});
}

class MockSpec<T> {
  final Symbol mockName;

  final bool returnNullOnMissingStub;

  final Set<Symbol> unsupportedMembers;

  final Map<Symbol, Function> fallbackGenerators;

  const MockSpec({
    Symbol? as,
    this.returnNullOnMissingStub = false,
    this.unsupportedMembers = const {},
    this.fallbackGenerators = const {},
  }) : mockName = as;
}
'''
};

const mockitoAssets = {
  'mockito|lib/mockito.dart': '''
export 'src/mock.dart';
''',
  'mockito|lib/src/mock.dart': '''
class Mock {}
'''
};

const simpleTestAsset = {
  'foo|test/foo_test.dart': '''
import 'package:foo/foo.dart';
import 'package:mockito/annotations.dart';
@GenerateMocks([], customMocks: [MockSpec<Foo>()])
void main() {}
'''
};

const _constructorWithThrowOnMissingStub = '''
MockFoo() {
    _i1.throwOnMissingStub(this);
  }''';

void main() {
  late InMemoryAssetWriter writer;

  /// Test [MockBuilder] in a package which has not opted into null safety.
  Future<void> testPreNonNullable(Map<String, String> sourceAssets,
      {Map<String, /*String|Matcher<String>*/ Object>? outputs}) async {
    var packageConfig = PackageConfig([
      Package('foo', Uri.file('/foo/'),
          packageUriRoot: Uri.file('/foo/lib/'),
          languageVersion: LanguageVersion(2, 7))
    ]);
    await testBuilder(buildMocks(BuilderOptions({})), sourceAssets,
        outputs: outputs, packageConfig: packageConfig);
  }

  /// Builds with [MockBuilder] in a package which has opted into null safety,
  /// returning the content of the generated mocks library.
  Future<String> buildWithNonNullable(Map<String, String> sourceAssets) async {
    var packageConfig = PackageConfig([
      Package('foo', Uri.file('/foo/'),
          packageUriRoot: Uri.file('/foo/lib/'),
          languageVersion: LanguageVersion(2, 12))
    ]);
    await testBuilder(buildMocks(BuilderOptions({})), sourceAssets,
        writer: writer, packageConfig: packageConfig);
    var mocksAsset = AssetId('foo', 'test/foo_test.mocks.dart');
    return utf8.decode(writer.assets[mocksAsset]!);
  }

  setUp(() {
    writer = InMemoryAssetWriter();
  });

  test('generates a generic mock class without type arguments', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(as: #MockFoo)])
        void main() {}
        '''
    });
    expect(mocksContent,
        contains('class MockFoo<T> extends _i1.Mock implements _i2.Foo<T>'));
  });

  test('without type arguments, generates generic method types', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {
          List<T> f;
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(as: #MockFoo)])
        void main() {}
        '''
    });
    expect(mocksContent, contains('List<T> get f =>'));
  });

  test('generates a generic mock class with deep type arguments', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        class Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks(
            [], customMocks: [MockSpec<Foo<List<Bar>>>(as: #MockFoo)])
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'class MockFoo extends _i1.Mock implements _i2.Foo<List<_i2.Bar>>'));
  });

  test('generates a generic mock class with type arguments', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T, U> {}
        class Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks(
            [], customMocks: [MockSpec<Foo<int, Bar>>(as: #MockFooOfIntBar)])
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'class MockFooOfIntBar extends _i1.Mock implements _i2.Foo<int, _i2.Bar>'));
  });

  test('generates a generic mock class with nullable type arguments', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T, U> {}
        class Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks(
            [], customMocks: [MockSpec<Foo<int?, Bar?>>(as: #MockFooOfIntBar)])
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'class MockFooOfIntBar extends _i1.Mock implements _i2.Foo<int?, _i2.Bar?>'));
  });

  test('generates a generic mock class with nested type arguments', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks(
            [], customMocks: [MockSpec<Foo<List<int>>>(as: #MockFooOfListOfInt)])
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'class MockFooOfListOfInt extends _i1.Mock implements _i2.Foo<List<int>>'));
  });

  test('generates a generic mock class with type arguments but no name',
      () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo<int>>()])
        void main() {}
        '''
    });
    expect(mocksContent,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo<int>'));
  });

  test('generates a generic, bounded mock class without type arguments',
      () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T extends Object> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(as: #MockFoo)])
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'class MockFoo<T extends Object> extends _i1.Mock implements _i2.Foo<T>'));
  });

  test('generates mock classes from multiple annotations', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo {}
        class Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>()])
        void fooTests() {}
        @GenerateMocks([], customMocks: [MockSpec<Bar>()])
        void barTests() {}
        '''
    });
    expect(mocksContent,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo'));
    expect(mocksContent,
        contains('class MockBar extends _i1.Mock implements _i2.Bar'));
  });

  test('generates mock classes from multiple annotations on a single element',
      () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/a.dart': dedent(r'''
        class Foo {}
        '''),
      'foo|lib/b.dart': dedent(r'''
        class Foo {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/a.dart' as a;
        import 'package:foo/b.dart' as b;
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<a.Foo>(as: #MockAFoo)])
        @GenerateMocks([], customMocks: [MockSpec<b.Foo>(as: #MockBFoo)])
        void main() {}
        '''
    });
    expect(mocksContent,
        contains('class MockAFoo extends _i1.Mock implements _i2.Foo'));
    expect(mocksContent,
        contains('class MockBFoo extends _i1.Mock implements _i3.Foo'));
  });

  test(
      'generates a mock class which uses the old behavior of returning null on '
      'missing stubs', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(as: #MockFoo, returnNullOnMissingStub: true)])
        void main() {}
        '''
    });
    expect(mocksContent, isNot(contains('throwOnMissingStub')));
  });

  test(
      'generates mock methods with non-nullable unknown types, given '
      'unsupportedMembers', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          T m<T>(T a);
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo>(unsupportedMembers: {#m}),
          ],
        )
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains('  T m<T>(T? a) => throw UnsupportedError(\n'
            r"      '\'m\' cannot be used without a mockito fallback generator.');"));
  });

  test('generates mock classes including a fallback generator for a getter',
      () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo<T> {
          T get f;
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        T fShim<T>() {
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo>(fallbackGenerators: {#f: fShim}),
          ],
        )
        void main() {}
        '''
    });
    expect(
      mocksContent,
      contains('T get f =>\n'
          '      (super.noSuchMethod(Invocation.getter(#f), returnValue: _i3.fShim())\n'
          '          as T);'),
    );
  });

  test(
      'generates mock classes including a fallback generator for a generic '
      'method with positional parameters', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          T m<T>(T a);
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        T mShim<T>(T a) {
          if (a is int) return 1;
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo>(as: #MockFoo, fallbackGenerators: {#m: mShim}),
          ],
        )
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'T m<T>(T? a) => (super.noSuchMethod(Invocation.method(#m, [a]),\n'
            '      returnValue: _i3.mShim<T>(a)) as T)'));
  });

  test(
      'generates mock classes including a fallback generator for a generic '
      'method on a super class', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent('''
        abstract class FooBase {
          T m<T>(T a);
        }
        abstract class Foo extends FooBase {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        T mShim<T>(T a) {
          if (a is int) return 1;
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo>(as: #MockFoo, fallbackGenerators: {#m: mShim}),
          ],
        )
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'T m<T>(T? a) => (super.noSuchMethod(Invocation.method(#m, [a]),\n'
            '      returnValue: _i3.mShim<T>(a)) as T)'));
  });

  test('generates mock classes including two fallback generators', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent('''
        abstract class Foo<S> {
          T m<T>(T a);
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        T mShimA<T>(T a) {
          throw 'unknown';
        }

        T mShimB<T>(T a) {
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo<int>>(as: #MockFooA, fallbackGenerators: {#m: mShimA}),
            MockSpec<Foo<String>>(as: #MockFooB, fallbackGenerators: {#m: mShimB}),
          ],
        )
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'T m<T>(T? a) => (super.noSuchMethod(Invocation.method(#m, [a]),\n'
            '      returnValue: _i3.mShimA<T>(a)) as T)'));
    expect(
        mocksContent,
        contains(
            'T m<T>(T? a) => (super.noSuchMethod(Invocation.method(#m, [a]),\n'
            '      returnValue: _i3.mShimB<T>(a)) as T)'));
  });

  test(
      'generates mock classes including a fallback generator for a generic '
      'method with positional parameters returning a Future of the generic',
      () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          Future<T> m<T>(T a);
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        Future<T> mShim<T>(T a) async {
          if (a is int) return 1;
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [MockSpec<Foo>(as: #MockFoo, fallbackGenerators: {#m: mShim})],
        )
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            '_i3.Future<T> m<T>(T? a) => (super.noSuchMethod(Invocation.method(#m, [a]),\n'
            '      returnValue: _i4.mShim<T>(a)) as _i3.Future<T>)'));
  });

  test(
      'generates mock classes including a fallback generator for a generic '
      'method with named parameters', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          T m<T>({T a});
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        T mShim<T>({T a}) {
          if (a is int) return 1;
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [MockSpec<Foo>(as: #MockFoo, fallbackGenerators: {#m: mShim})],
        )
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains(
            'T m<T>({T? a}) => (super.noSuchMethod(Invocation.method(#m, [], {#a: a}),\n'
            '      returnValue: _i3.mShim<T>(a: a)) as T);'));
  });

  test(
      'generates mock classes including a fallback generator for a bounded '
      'generic method with named parameters', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          T m<T extends num>({T a});
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        T mShim<T extends num>({T a}) {
          if (a is int) return 1;
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [MockSpec<Foo>(as: #MockFoo, fallbackGenerators: {#m: mShim})],
        )
        void main() {}
        '''
    });
    expect(
        mocksContent,
        contains('T m<T extends num>({T? a}) =>\n'
            '      (super.noSuchMethod(Invocation.method(#m, [], {#a: a}),\n'
            '          returnValue: _i3.mShim<T>(a: a)) as T);'));
  });

  test(
      'generates mock classes including a fallback generator for a generic '
      'method with a parameter with a function-typed type argument with '
      'unknown return type', () async {
    var mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          T m<T>({List<T Function()> a});
        }
        '''),
      'foo|test/foo_test.dart': dedent('''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        T mShim<T>({List<T Function()> a}) {
          throw 'unknown';
        }

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo>(as: #MockFoo, fallbackGenerators: {#m: mShim}),
          ],
        )
        void main() {}
        ''')
    });
    expect(
        mocksContent,
        contains('T m<T>({List<T Function()>? a}) =>\n'
            '      (super.noSuchMethod(Invocation.method(#m, [], {#a: a}),\n'
            '          returnValue: _i3.mShim<T>(a: a)) as T);'));
  });

  test(
      'throws when GenerateMocks is given a class with a type parameter with a '
      'private bound', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo<T extends _Bar> {
          void m(int a) {}
        }
        class _Bar {}
        '''),
        'foo|test/foo_test.dart': dedent('''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>()])
        void main() {}
        '''),
      },
      message: contains(
          "The class 'Foo' features a private type parameter bound, and cannot "
          'be stubbed.'),
    );
  });

  test('throws when MockSpec() is missing a type argument', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        // Missing required type argument to MockSpec.
        @GenerateMocks([], customMocks: [MockSpec()])
        void main() {}
        '''),
      },
      message: contains('Mockito cannot mock `dynamic`'),
    );
  });

  test('throws when MockSpec uses a private class', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<_Foo>()])
        void main() {}
        class _Foo {}
        '''),
      },
      message: contains('Mockito cannot mock a private type: _Foo.'),
    );
  });

  test('throws when two distinct classes with the same name are mocked',
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
        @GenerateMocks([], customMocks: [MockSpec<a.Foo>()])
        @GenerateMocks([], customMocks: [MockSpec<b.Foo>()])
        void main() {}
        '''),
      },
      message: contains(
          'Mockito cannot generate two mocks with the same name: MockFoo (for '
          'Foo declared in /foo/lib/a.dart, and for Foo declared in '
          '/foo/lib/b.dart)'),
    );
  });

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
        @GenerateMocks([], customMocks: [MockSpec<Foo>()])
        void main() {}
        class MockFoo {}
        '''),
      },
      message: contains(
          'Mockito cannot generate a mock with a name which conflicts with '
          'another class declared in this library: MockFoo'),
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
        @GenerateMocks([], customMocks: [MockSpec<Foo>()])
        void main() {}
        class FakeFoo extends Mock implements Foo {}
        '''),
      },
      message: contains(
          'contains a class which appears to already be mocked inline: FakeFoo'),
    );
  });

  test('throws when MockSpec references a typedef', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        typedef Foo = void Function();
        '''),
      },
      message: 'Mockito cannot mock a typedef: Foo',
    );
  });

  test('throws when MockSpec references an enum', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        enum Foo {}
        '''),
      },
      message: 'Mockito cannot mock an enum: Foo',
    );
  });

  test('throws when MockSpec references a non-subtypeable type', () async {
    _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<int>()])
        void main() {}
        '''),
      },
      message: contains('Mockito cannot mock a non-subtypable type: int'),
    );
  });

  test('given a pre-non-nullable library, does not override any members',
      () async {
    await testPreNonNullable(
      {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          int f(int a);
        }
        '''),
      },
      outputs: {
        'foo|test/foo_test.mocks.dart': _containsAllOf(dedent('''
        class MockFoo extends _i1.Mock implements _i2.Foo {
          $_constructorWithThrowOnMissingStub
        }
        '''))
      },
    );
  });

  test(
      'given a pre-non-nullable safe library, does not write "?" on interface '
      'types', () async {
    await testPreNonNullable(
      {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo<T> {
          int f(int a);
        }
        '''),
        'foo|test/foo_test.dart': dedent('''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks(
            [], customMocks: [MockSpec<Foo<int>>(as: #MockFoo)])
        void main() {}
        '''),
      },
      outputs: {
        'foo|test/foo_test.mocks.dart': _containsAllOf(dedent('''
        class MockFoo extends _i1.Mock implements _i2.Foo<int> {
          $_constructorWithThrowOnMissingStub
        }
        '''))
      },
    );
  });
}

TypeMatcher<List<int>> _containsAllOf(a, [b]) => decodedMatches(
    b == null ? allOf(contains(a)) : allOf(contains(a), contains(b)));

/// Expect that [testBuilder], given [assets], throws an
/// [InvalidMockitoAnnotationException] with a message containing [message].
void _expectBuilderThrows({
  required Map<String, String> assets,
  required dynamic /*String|Matcher<List<int>>*/ message,
}) {
  expect(
      () async => await testBuilder(buildMocks(BuilderOptions({})), assets),
      throwsA(TypeMatcher<InvalidMockitoAnnotationException>()
          .having((e) => e.message, 'message', message)));
}

/// Dedent [input], so that each line is shifted to the left, so that the first
/// line is at the 0 column.
String dedent(String input) {
  final indentMatch = RegExp(r'^(\s*)').firstMatch(input)!;
  final indent = ''.padRight(indentMatch.group(1)!.length);
  return input.splitMapJoin('\n',
      onNonMatch: (s) => s.replaceFirst(RegExp('^$indent'), ''));
}
