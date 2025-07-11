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
library;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/src/builder.dart';
import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

import 'contains_ignoring_formatting.dart';

Builder buildMocks(BuilderOptions options) => MockBuilder();

const annotationsAsset = {
  'mockito|lib/annotations.dart': '''
class GenerateMocks {
  final List<Type> classes;
  final List<MockSpec> customMocks;

  const GenerateMocks(this.classes, {this.customMocks = []});
}

class GenerateNiceMocks {
  final List<MockSpec> mocks;

  const GenerateNiceMocks(this.mocks);
}

class MockSpec<T> {
  final Symbol? mockName;

  final List<Type> mixins;

  final OnMissingStub? onMissingStub;

  final Set<Symbol> unsupportedMembers;

  final Map<Symbol, Function> fallbackGenerators;

  const MockSpec({
    Symbol? as,
    List<Type> mixingIn = const [],
    this.onMissingStub,
    this.unsupportedMembers = const {},
    this.fallbackGenerators = const {},
  })  : mockName = as,
        mixins = mixingIn;
}

enum OnMissingStub { throwException, returnDefault }
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

const simpleTestAsset = {
  'foo|test/foo_test.dart': '''
import 'package:foo/foo.dart';
import 'package:mockito/annotations.dart';
@GenerateMocks([], customMocks: [MockSpec<Foo>()])
void main() {}
''',
};

void main() {
  late TestReaderWriter readerWriter;

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
    final builder = buildMocks(BuilderOptions({}));
    await testBuilders(
      [builder],
      visibleOutputBuilders: {builder},
      sourceAssets,
      rootPackage: 'foo',
      readerWriter: readerWriter,
      packageConfig: packageConfig,
    );
    final mocksAsset = AssetId('foo', 'test/foo_test.mocks.dart');
    return readerWriter.testing.readString(mocksAsset);
  }

  setUp(() {
    readerWriter = TestReaderWriter(rootPackage: 'foo');
  });

  test('generates a generic mock class without type arguments', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(as: #MockFoo)])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      contains('class MockFoo<T> extends _i1.Mock implements _i2.Foo<T>'),
    );
  });

  test('without type arguments, generates generic method types', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(mocksContent, contains('List<T> get f =>'));
  });

  test('generates a generic mock class with deep type arguments', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFoo extends _i1.Mock implements _i2.Foo<List<_i2.Bar>>',
      ),
    );
  });

  test('generates a generic mock class with type arguments', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFooOfIntBar extends _i1.Mock implements _i2.Foo<int, _i2.Bar>',
      ),
    );
  });

  test(
    'generates a generic mock class with lower bound type arguments',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo<T, U extends Bar> {}
        class Bar {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks(
            [], customMocks: [MockSpec<Foo<dynamic, Bar>>(as: #MockFoo)])
        void main() {}
        ''',
      });
      expect(
        mocksContent,
        contains(
          'class MockFoo extends _i1.Mock implements _i2.Foo<dynamic, _i2.Bar>',
        ),
      );
    },
  );

  test('generates a generic mock class with nullable type arguments', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFooOfIntBar extends _i1.Mock implements _i2.Foo<int?, _i2.Bar?>',
      ),
    );
  });

  test('generates a generic mock class with nested type arguments', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFooOfListOfInt extends _i1.Mock implements _i2.Foo<List<int>>',
      ),
    );
  });

  test(
    'generates a generic mock class with type arguments but no name',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo<int>>()])
        void main() {}
        ''',
      });
      expect(
        mocksContent,
        contains('class MockFoo extends _i1.Mock implements _i2.Foo<int>'),
      );
    },
  );

  test(
    'generates a generic, bounded mock class without type arguments',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo<T extends Object> {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(as: #MockFoo)])
        void main() {}
        ''',
      });
      expect(
        mocksContent,
        contains(
          'class MockFoo<T extends Object> extends _i1.Mock implements _i2.Foo<T>',
        ),
      );
    },
  );

  test('generates mock classes from multiple annotations', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(
      mocksContent,
      contains('class MockFoo extends _i1.Mock implements _i2.Foo'),
    );
    expect(
      mocksContent,
      contains('class MockBar extends _i1.Mock implements _i2.Bar'),
    );
  });

  test(
    'generates mock classes from multiple annotations on a single element',
    () async {
      final mocksContent = await buildWithNonNullable({
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
        ''',
      });
      expect(
        mocksContent,
        contains('class MockAFoo extends _i1.Mock implements _i2.Foo'),
      );
      expect(
        mocksContent,
        contains('class MockBFoo extends _i1.Mock implements _i3.Foo'),
      );
    },
  );

  test('generates a mock class with a declared mixin', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent('''
        class Foo {}

        class FooMixin implements Foo {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(mixingIn: [FooMixin])])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFoo extends _i1.Mock with _i2.FooMixin implements _i2.Foo {',
      ),
    );
  });

  test('generates a mock class with multiple declared mixins', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent('''
        class Foo {}

        class Mixin1 implements Foo {}
        class Mixin2 implements Foo {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(mixingIn: [Mixin1, Mixin2])])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFoo extends _i1.Mock with _i2.Mixin1, _i2.Mixin2 implements _i2.Foo {',
      ),
    );
  });

  test('generates a mock class with a declared mixin with a type arg', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent('''
        class Foo<T> {}

        class FooMixin<T> implements Foo<T> {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo<int>>(mixingIn: [FooMixin<int>])])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFoo extends _i1.Mock with _i2.FooMixin<int> implements _i2.Foo<int> {',
      ),
    );
  });

  test('generates a mock class with a marker mixin', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': '''
        class Foo {}
        class FooMarkerMixin {}
        ''',
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [
          MockSpec<Foo>(mixingIn: [FooMarkerMixin])
        ])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      contains(
        'class MockFoo extends _i1.Mock with _i2.FooMarkerMixin implements _i2.Foo {',
      ),
    );
  });

  test('generates mock methods with private return types, given '
      'unsupportedMembers', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          _Bar m();
        }
        class _Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateNiceMocks([
          MockSpec<Foo>(unsupportedMembers: {#m}),
        ])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      containsIgnoringFormatting(
        'm() => throw UnsupportedError('
        'r\'"m" cannot be used without a mockito fallback generator.\'',
      ),
    );
  });

  test(
    'generates mock getters with private types, given unsupportedMembers',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          _Bar get f;
        }
        class _Bar {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateNiceMocks([
          MockSpec<Foo>(unsupportedMembers: {#f}),
        ])
        void main() {}
        ''',
      });
      expect(
        mocksContent,
        containsIgnoringFormatting(
          'get f => throw UnsupportedError('
          'r\'"f" cannot be used without a mockito fallback generator.\'',
        ),
      );
    },
  );

  test(
    'generates mock setters with private types, given unsupportedMembers',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent('''
        abstract class Foo {
          set f(_Bar value);
        }
        class _Bar {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateNiceMocks([
          MockSpec<Foo>(unsupportedMembers: {Symbol('f=')}),
        ])
        void main() {}
        ''',
      });
      expect(
        mocksContent,
        containsIgnoringFormatting(
          'set f(value) => throw UnsupportedError('
          'r\'"f=" cannot be used without a mockito fallback generator.\'',
        ),
      );
    },
  );

  test('generates mock methods with return types with private names in type '
      'arguments, given unsupportedMembers', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          List<_Bar> m();
        }
        class _Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateNiceMocks([
          MockSpec<Foo>(unsupportedMembers: {#m}),
        ])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      containsIgnoringFormatting(
        'm() => throw UnsupportedError('
        'r\'"m" cannot be used without a mockito fallback generator.\'',
      ),
    );
  });

  test(
    'generates mock methods with return types with private names in function '
    'types, given unsupportedMembers',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          void Function(_Bar) m();
        }
        class _Bar {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateNiceMocks([
          MockSpec<Foo>(unsupportedMembers: {#m}),
        ])
        void main() {}
        ''',
      });
      expect(
        mocksContent,
        containsIgnoringFormatting(
          'm() => throw UnsupportedError('
          'r\'"m" cannot be used without a mockito fallback generator.\'',
        ),
      );
    },
  );

  test('generates mock methods with private parameter types, given '
      'unsupportedMembers', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          void m(_Bar b);
        }
        class _Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateNiceMocks([
          MockSpec<Foo>(unsupportedMembers: {#m}),
        ])
        void main() {}
        ''',
    });
    expect(
      mocksContent,
      containsIgnoringFormatting(
        'void m(b) => throw UnsupportedError('
        'r\'"m" cannot be used without a mockito fallback generator.\'',
      ),
    );
  });

  test('generates mock methods with non-nullable return types, specifying '
      'legal default values for basic known types', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          int m();
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo>(onMissingStub: OnMissingStub.returnDefault),
          ],
        )
        void main() {}
        ''',
    });
    expect(mocksContent, contains('returnValue: 0,'));
    expect(mocksContent, contains('returnValueForMissingStub: 0,'));
  });

  test('generates mock methods with non-nullable return types, specifying '
      'legal default values for unknown types', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        abstract class Foo {
          Bar m();
        }
        class Bar {}
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        @GenerateMocks(
          [],
          customMocks: [
            MockSpec<Foo>(onMissingStub: OnMissingStub.returnDefault),
          ],
        )
        void main() {}
        ''',
    });

    expect(
      mocksContent,
      containsIgnoringFormatting('''
        returnValue: _FakeBar_0(this, Invocation.method(#m, [])),
        returnValueForMissingStub: _FakeBar_0(
          this,
          Invocation.method(#m, []),
        )'''),
    );
  });

  test(
    'generates mock classes including a fallback generator for a getter',
    () async {
      final mocksContent = await buildWithNonNullable({
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
        ''',
      });
      expect(mocksContent, contains('returnValue: _i3.fShim()'));
    },
  );

  test('generates mock classes including a fallback generator for a generic '
      'method with positional parameters', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(mocksContent, contains('returnValue: _i3.mShim<T>(a),'));
  });

  test('generates mock classes including a fallback generator for a generic '
      'method on a super class', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(mocksContent, contains('returnValue: _i3.mShim<T>(a),'));
  });

  test('generates mock classes including two fallback generators', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(mocksContent, contains('returnValue: _i3.mShimA<T>(a),'));
    expect(mocksContent, contains('returnValue: _i3.mShimB<T>(a),'));
  });

  test(
    'generates mock classes including a fallback generator for a generic '
    'method with positional parameters returning a Future of the generic',
    () async {
      final mocksContent = await buildWithNonNullable({
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
        ''',
      });
      expect(mocksContent, contains('returnValue: _i4.mShim<T>(a),'));
    },
  );

  test('generates mock classes including a fallback generator for a generic '
      'method with named parameters', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(mocksContent, contains('returnValue: _i3.mShim<T>(a: a),'));
  });

  test('generates mock classes including a fallback generator for a bounded '
      'generic method with named parameters', () async {
    final mocksContent = await buildWithNonNullable({
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
        ''',
    });
    expect(mocksContent, contains('returnValue: _i3.mShim<T>(a: a),'));
  });

  test('generates mock classes including a fallback generator for a generic '
      'method with a parameter with a function-typed type argument with '
      'unknown return type', () async {
    final mocksContent = await buildWithNonNullable({
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
        '''),
    });
    expect(mocksContent, contains('returnValue: _i3.mShim<T>(a: a),'));
  });

  test('generates mock classes including a fallback generator and '
      'OnMissingStub.returnDefault', () async {
    final mocksContent = await buildWithNonNullable({
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
            MockSpec<Foo>(
                fallbackGenerators: {#f: fShim},
                onMissingStub: OnMissingStub.returnDefault),
          ],
        )
        void main() {}
        ''',
    });
    expect(mocksContent, contains('returnValue: _i3.fShim(),'));
    expect(mocksContent, contains('returnValueForMissingStub: _i3.fShim(),'));
  });

  test(
    'throws when GenerateMocks is given a class with a type parameter with a '
    'private bound',
    () async {
      await _expectBuilderThrows(
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
          'be stubbed.',
        ),
      );
    },
  );

  test('throws when MockSpec() is missing a type argument', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        // Missing required type argument to MockSpec.
        @GenerateMocks([], customMocks: [MockSpec()])
        void main() {}
        '''),
      },
      message: contains(
        'MockSpec requires a type argument to determine the class to mock',
      ),
    );
  });

  test('throws when MockSpec() is given an unknown type argument', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        // Missing required type argument to MockSpec.
        @GenerateMocks([], customMocks: [MockSpec<Unknown>()])
        void main() {}
        '''),
      },
      message: contains('Mockito cannot mock unknown type `Unknown`'),
    );
  });

  test('throws when MockSpec uses a private class', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<_Foo>()])
        void main() {}
        class _Foo {}
        '''),
      },
      message: contains("Mockito cannot mock a private type: '_Foo'."),
    );
  });

  test(
    'throws when two distinct classes with the same name are mocked',
    () async {
      await _expectBuilderThrows(
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
          '/foo/lib/b.dart)',
        ),
      );
    },
  );

  test('throws when a mock class of the same name already exists', () async {
    await _expectBuilderThrows(
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
        'another class declared in this library: MockFoo',
      ),
    );
  });

  test('throws when a mock class of class-to-mock already exists', () async {
    await _expectBuilderThrows(
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
        'contains a class which appears to already be mocked inline: FakeFoo',
      ),
    );
  });

  test('throws when MockSpec references a function typedef', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        typedef Foo = void Function();
        '''),
      },
      message: contains('Mockito cannot mock a non-class: Foo'),
    );
  });

  test('throws when MockSpec references an enum', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        ...simpleTestAsset,
        'foo|lib/foo.dart': dedent(r'''
        enum Foo {}
        '''),
      },
      message: contains("Mockito cannot mock an enum: 'Foo'"),
    );
  });

  test('throws when MockSpec references a non-subtypeable type', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        @GenerateMocks([], customMocks: [MockSpec<int>()])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a non-subtypable type: 'int'"),
    );
  });

  test('throws when GenerateMocks references a sealed class', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        sealed class Foo {}
        @GenerateMocks([], customMocks: [MockSpec<Foo>()])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a sealed class 'Foo'"),
    );
  });

  test(
    'throws when GenerateMocks references sealed a class via typedef',
    () async {
      await _expectBuilderThrows(
        assets: {
          ...annotationsAsset,
          'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        sealed class Foo {}
        typedef Bar = Foo;
        @GenerateMocks([], customMocks: [MockSpec<Bar>()])
        void main() {}
        '''),
        },
        message: contains("Mockito cannot mock a sealed class 'Foo'"),
      );
    },
  );

  test('throws when GenerateMocks references a base class', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        base class Foo {}
        @GenerateMocks([], customMocks: [MockSpec<Foo>()])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a base class 'Foo'"),
    );
  });

  test('throws when GenerateMocks references a final class', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|test/foo_test.dart': dedent('''
        // @dart=3.0
        import 'package:mockito/annotations.dart';
        final class Foo {}
        @GenerateMocks([], customMocks: [MockSpec<Foo>()])
        void main() {}
        '''),
      },
      message: contains("Mockito cannot mock a final class 'Foo'"),
    );
  });

  test('throws when MockSpec mixes in dynamic', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent('''
        class Foo {}
        '''),
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        import 'package:foo/foo.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(mixingIn: [dynamic])])
        void main() {}
        '''),
      },
      message: contains('Mockito cannot mix `dynamic` into a mock class'),
    );
  });

  test('throws when MockSpec mixes in a private type', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent('''
        class Foo {}
        '''),
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        import 'package:foo/foo.dart';
        @GenerateMocks([], customMocks: [MockSpec<Foo>(mixingIn: [_FooMixin])])
        void main() {}

        mixin _FooMixin implements Foo {}
        '''),
      },
      message: contains("Mockito cannot mock a private type: '_FooMixin'"),
    );
  });

  test('throws when type argument is unknown type', () async {
    await _expectBuilderThrows(
      assets: {
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent('''
        class Bar {}
        class Foo<T> {}
        '''),
        'foo|test/foo_test.dart': dedent('''
        import 'package:mockito/annotations.dart';
        import 'package:foo/foo.dart';
        @GenerateMocks([Bar], customMocks: [MockSpec<Foo<MockBar>>()])
        void main() {}
        '''),
      },
      message: contains('Undefined type MockBar'),
    );
  });

  test(
    'generates a mock class which uses the new behavior of returning '
    'a valid value for missing stubs, if GenerateNiceMocks were used',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Bar {}
        abstract class Foo<T> {
          int m();
          Bar get f;
        }
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateNiceMocks([MockSpec<Foo>()])
        void main() {}
        ''',
      });
      expect(mocksContent, isNot(contains('throwOnMissingStub')));
      expect(mocksContent, contains('returnValue: 0'));
      expect(mocksContent, contains('returnValueForMissingStub: 0'));
      expect(mocksContent, contains('returnValue: _FakeBar_0('));
      expect(mocksContent, contains('returnValueForMissingStub: _FakeBar_0('));
    },
  );

  test('generates a mock class which uses the new behavior of returning '
      'a valid value for missing stubs, if GenerateNiceMocks and '
      'fallbackGenerators were used', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {
          int m();
        }
        '''),
      'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';

        int mShim() {
          return 1;
        }

        @GenerateNiceMocks([MockSpec<Foo>(fallbackGenerators: {#m: mShim})])
        void main() {}
        ''',
    });
    expect(mocksContent, isNot(contains('throwOnMissingStub')));
    expect(mocksContent, contains('returnValue: _i3.mShim(),'));
    expect(mocksContent, contains('returnValueForMissingStub: _i3.mShim(),'));
  });

  test(
    'mixed GenerateMocks and GenerateNiceMocks annotations could be used',
    () async {
      final mocksContent = await buildWithNonNullable({
        ...annotationsAsset,
        'foo|lib/foo.dart': dedent(r'''
        class Foo<T> {}
        class Bar {}
        '''),
        'foo|test/foo_test.dart': '''
        import 'package:foo/foo.dart';
        import 'package:mockito/annotations.dart';
        @GenerateNiceMocks([MockSpec<Foo>()])
        @GenerateMocks([], customMocks: [MockSpec<Bar>()])
        void main() {}
        ''',
      });
      expect(mocksContent, contains('class MockFoo'));
      expect(mocksContent, contains('class MockBar'));
    },
  );

  group('typedef mocks', () {
    group('are generated properly', () {
      test('when all aliased type parameters are instantiated', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A, B, C> {}
            typedef Bar = Foo<int, bool, String>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateNiceMocks([
              MockSpec<Bar>(),
            ])
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
            @GenerateNiceMocks([
              MockSpec<Bar>(),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar'));
      });

      test('when the typedef defines a type and it corresponds to a different '
          'index of the aliased type', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A> {}
            typedef Bar<X> = Foo<num, X>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateNiceMocks([
              MockSpec<Bar<int>>(),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar<int>'));
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
            @GenerateNiceMocks([
              MockSpec<Bar>(),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar'));
      });

      test('when the mock instantiates another typedef', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A> {}
            typedef Bar<B> = Foo<B>;

            class Baz<X> {}
            typedef Qux<Y> = Baz<Y>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateNiceMocks([
              MockSpec<Qux<Bar<int>>>(),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockQux extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Qux<_i2.Foo<int>>'));
      });

      test('when the typedef defines a bounded class type and it is NOT '
          'instantiated', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A> {}
            class Bar {}
            typedef Baz<X extends Bar> = Foo<X>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateNiceMocks([
              MockSpec<Baz>(),
            ])
            void main() {}
          ''',
        });

        expect(
          mocksContent,
          contains('class MockBaz<X extends _i1.Bar> extends _i2.Mock'),
        );
        expect(mocksContent, contains('implements _i1.Baz<X>'));
      });

      test('when the typedef defines a bounded type and the mock instantiates '
          'it', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A> {}
            typedef Bar<X extends num> = Foo<X>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';
            @GenerateNiceMocks([
              MockSpec<Bar<int>>(),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBar extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Bar<int>'));
      });

      test('when the aliased type has a parameterized method', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A> {
              A get value;
            }
          '''),
          'bar|lib/bar.dart': dedent(r'''
            import 'package:foo/foo.dart';
            typedef Bar = Foo<String>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:bar/bar.dart';
            import 'package:mockito/annotations.dart';
            @GenerateNiceMocks([
              MockSpec<Bar>(),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('String get value'));
      });

      test('when the typedef is parameterized and the aliased type has a '
          'parameterized method', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            class Foo<A> {
              A get value;
            }
          '''),
          'bar|lib/bar.dart': dedent(r'''
            import 'package:foo/foo.dart';
            typedef Bar<T> = Foo<T>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:bar/bar.dart';
            import 'package:mockito/annotations.dart';

            X fallbackGenerator<X>() {
              throw 'unknown';
            }

            @GenerateNiceMocks([
              MockSpec<Bar>(fallbackGenerators: {#value: fallbackGenerator}),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('T get value'));
      });

      test('when the aliased type is a mixin', () async {
        final mocksContent = await buildWithNonNullable({
          ...annotationsAsset,
          'foo|lib/foo.dart': dedent(r'''
            mixin Foo {
              String get value;
            }

             typedef Bar = Foo<String>;
          '''),
          'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateNiceMocks([
              MockSpec<Bar>(),
            ])
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

            @GenerateNiceMocks([
              MockSpec<Baz>(),
            ])
            void main() {}
          ''',
        });

        expect(mocksContent, contains('class MockBaz extends _i1.Mock'));
        expect(mocksContent, contains('implements _i2.Baz'));
      });
    });

    test('generation throws when the aliased type is nullable', () async {
      await _expectBuilderThrows(
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

            @GenerateNiceMocks([MockSpec<Bar>()])
            void main() {}
          ''',
        },
        message: contains(
          'Mockito cannot mock a type-aliased nullable type: Bar',
        ),
      );
    });
  });
  test('Void in argument type coming from type arg becomes dynamic', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
      class Foo<T> {
        T m(T x) => x;
      }
      '''),
      'foo|test/foo_test.dart': dedent(r'''
      import 'package:foo/foo.dart';
      import 'package:mockito/annotations.dart';

      @GenerateMocks([], customMocks: [MockSpec<Foo<void>>()])
      void main() {}
      '''),
    });
    expect(mocksContent, contains('void m(dynamic x)'));
  });
  test('We rename clashing type variables', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
            abstract class Foo<E> {
              Iterable<T> map<T>(T Function(E) f);
            }

            abstract class Bar<T> extends Foo<T> {}
        '''),
      'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateNiceMocks([
              MockSpec<Bar>(),
            ])
            void main() {}
          ''',
    });
    expect(mocksContent, contains('Iterable<T1> map<T1>(T1 Function(T)? f)'));
  });
  test('We rename clashing type variables in type aliases', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
            abstract class Foo<E> {
              Iterable<T> map<T>(T Function(E) f);
            }

            typedef Bar<T> = Foo<T>;
        '''),
      'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateNiceMocks([
              MockSpec<Bar>(),
            ])
            void main() {}
          ''',
    });
    expect(mocksContent, contains('Iterable<T1> map<T1>(T1 Function(T)? f)'));
  });
  test('We rename clashing type variables in function literals', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
            typedef Fun<E> = List<E> Function<T>(T);
            abstract class Foo<T> {
              Fun<T> m();
            }
        '''),
      'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateNiceMocks([
              MockSpec<Foo>(),
            ])
            void main() {}
          ''',
    });
    expect(mocksContent, contains('returnValue: <T1>(T1 __p0) => <T>[]'));
  });
  // Here rename in not needed, but the code does it.
  test('We rename obscure type variables', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
            abstract class Foo<T> {
              Iterable<T> m<T>(T Function() f);
            }
        '''),
      'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateNiceMocks([
              MockSpec<Foo>(),
            ])
            void main() {}
          ''',
    });
    expect(mocksContent, contains('Iterable<T1> m<T1>(T1 Function()? f)'));
  });
  test('We do not rename unrelated type variables', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
            class Foo<T> {}
            abstract class Bar<T> {
              Iterable<X> m1<X>(X Function(T) f);
              Iterable<X?> m2<X>(X Function(T) f);
            }
            abstract class FooBar<X> extends Bar<X> {}
        '''),
      'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateNiceMocks([
              MockSpec<Foo>(), MockSpec<Bar>(), MockSpec<FooBar>()
            ])
            void main() {}
          ''',
    });
    expect(mocksContent, contains('class MockBar<T>'));
    expect(mocksContent, contains('class MockFooBar<X>'));
    expect(mocksContent, contains('Iterable<X1> m1<X1>(X1 Function(X)? f)'));
    expect(mocksContent, contains('Iterable<X1?> m2<X1>(X1 Function(X)? f)'));
  });
  test('We preserve nested generic bounded type arguments', () async {
    final mocksContent = await buildWithNonNullable({
      ...annotationsAsset,
      'foo|lib/foo.dart': dedent(r'''
            class Foo<A, B> {}
            abstract class Bar<T> {
              X m1<X extends Foo<Foo<X, T>, X>>(X Function(T)? f);
            }
            abstract class FooBar<X> extends Bar<X> {}
        '''),
      'foo|test/foo_test.dart': '''
            import 'package:foo/foo.dart';
            import 'package:mockito/annotations.dart';

            @GenerateMocks([FooBar])
            void main() {}
          ''',
    });
    expect(
      mocksContent,
      contains(
        'X1 m1<X1 extends _i2.Foo<_i2.Foo<X1, X>, X1>>(X1 Function(X)? f)',
      ),
    );
  });
}

/// Expect that [testBuilder], given [assets], throws an
/// [InvalidMockitoAnnotationException] with a message containing [message].
Future<void> _expectBuilderThrows({
  required Map<String, String> assets,
  required dynamic /*String|Matcher<List<int>>*/ message,
}) async {
  final logs = <String>[];
  await testBuilders(
    [buildMocks(BuilderOptions({}))],
    assets,
    rootPackage: 'foo',
    onLog: (r) {
      if (r.level == Level.SEVERE) {
        logs.add(r.toString());
      }
    },
  );
  expect(logs, contains(message));
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
