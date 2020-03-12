import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  final templatePath = p.join('tool', 'travis_template.yaml');
  final templateContent = File(templatePath).readAsStringSync();

  final templateMap =
      loadYaml(templateContent, sourceUrl: templatePath) as YamlMap;

  print(JsonEncoder.withIndent(' ').convert(_transform(templateMap, [])));
}

const _sdks = ['dev', '2.8.0-dev.6.0', 'stable'];

Object _transform(Object input, List<String> path) {
  if (input is YamlMap) {
    return _transformMap(input, path);
  } else if (input is YamlList) {
    final list = input.map((element) => _transform(element, path)).toList();
    if (p.joinAll(path) == 'jobs/include') {
      return list.cast<Map<String, dynamic>>().expand((element) {
        return _sdks.map((e) {
          final newValue = {
            ...element,
            'dart': e,
          };
          newValue['name'] = '${newValue['name']} - $e';
          return newValue;
        }).toList();
      }).toList();
    } else {
      return list;
    }
  } else if (input is String) {
    return input;
  }
  throw UnimplementedError(input.runtimeType.toString());
}

Map<String, dynamic> _transformMap(YamlMap map, List<String> path) {
  final value = <String, dynamic>{};
  for (var entry in map.entries) {
    if (path.isEmpty && entry.key == 'dart') {
      continue;
    }
    value[entry.key] = _transform(entry.value, [...path, entry.key]);
  }
  return value;
}
