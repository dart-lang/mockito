import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  final templatePath = p.join('tool', 'travis_template.yaml');
  final templateContent = File(templatePath).readAsStringSync();

  final templateMap =
      loadYaml(templateContent, sourceUrl: templatePath) as YamlMap;

  print(JsonEncoder.withIndent(' ').convert(templateMap));
}
