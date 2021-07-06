import 'dart:io';
import 'package:git/git.dart';
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;

import 'constants.dart';
import 'build.dart';

main(args) => grind(args);

List<String> examples = [];

@Task('Clean fragments (code excerpts)')
void cleanFrags() {
  if (Directory(fragPath).existsSync()) {
    delete(Directory(fragPath));
  }
}

@Task('Create code excerpts')
void createCodeExcerpts() {
  Pub.get();

  // Check if tmp/_fragments exists
  // It will create one if not
  if (!Directory(fragPath).existsSync()) {
    Directory(fragPath).createSync(recursive: true);
  }

  // Generate code excerpts
  Pub.run(
    'build_runner',
    arguments: [
      'build',
      '--delete-conflicting-outputs',
      '--config',
      'excerpt',
      '--output=$fragPath'
    ],
  );
}

@Task('Update code excerpts in Markdown files')
void updateCodeExcerpts() {
  Pub.run(
    'code_excerpt_updater',
    arguments: [
      srcPath,
      '--fragment-dir-path',
      fragPath,
      '--indentation',
      '2',
      '--write-in-place',
      'tmp/code-excerpt-log.txt',
      '--escape-ng-interpolation',
      '--yaml',
      File('tool/regex.txt')
          .readAsStringSync(), // A work around because for whatever reason Dart just doesn't recognize it
    ],
  );
}

@Task('Build site')
@Depends('clean-frags', 'create-code-excerpts', 'update-code-excerpts',
    'cp-built-examples')
void build() {
  TaskArgs args = context.invocation.arguments;

  // Run `bundle install`, similar to `pub get` in Dart
  run('bundle', arguments: ['install']);

  // Build site using [Jekyll](https://jekyllrb.com)
  run(
    'bundle',
    arguments: [
      'exec',
      'jekyll',
      'build',
    ],
  );
}

@DefaultTask()
void usage() => print('Run `grind --help` to list available tasks.');

@Task('Check and activate required global packages')
void activatePkgs() {
  PubApp webdev = PubApp.global('webdev');
  PubApp dartdoc = PubApp.global('dartdoc');

  if (!webdev.isActivated) {
    webdev.activate();
  }
  if (!webdev.isGlobal) {
    throw GrinderException(
        'Can\'t find webdev! Did you add \"~/.pub-cache\" to your environment variables?');
  }
  log('webdev is activated');

  if (!dartdoc.isActivated) {
    dartdoc.activate();
  }
  if (!dartdoc.isGlobal) {
    throw GrinderException(
        'Can\'t find dartdoc! Did you add \"~/.pub-cache\" to your environment variables?');
  }
  log('dartdoc is activated');
}

@Task('Get the list of examples')
void getExampleList() {
  if (examples.isEmpty) {
    Directory('examples/acx').listSync().forEach((element) {
      if (element is Directory) {
        examples.add(p.basename(element.path));
      }
    });
    Directory('examples/ng/doc').listSync().forEach((element) {
      if (element is Directory) {
        // All examples don't contain "_" symbol in their names
        if (!p.basename(element.path).contains('_')) {
          examples.add(p.basename(element.path));
        }
      }
    });

    examples.sort();
  }

  log('bruh');
}

/// Every example has a corresponding live example.
/// We always upload the latest build to a Github repo,
/// so that we don't have to build an example for it to show
/// up on the site everytime
@Task('Get built examples')
@Depends('get-example-list')
void getBuiltExamples() async {
  if (!builtExamplesDir.existsSync()) {
    builtExamplesDir.createSync(recursive: true);
  }

  // We only need gh-pages branch
  Future<void> pullRepo(String name) async => await runGit(
        [
          'clone',
          'https://github.com/angulardart-community/$name',
          '--branch',
          'gh-pages',
          '--single-branch',
          name,
          '--depth',
          '1'
        ],
        processWorkingDir: builtExamplesDir.path,
      );

  for (String example in examples) {
    await pullRepo(example);
  }
}

@Task('Copy built examples to the site folder')
@Depends('get-built-examples')
void cpBuiltExamples() {
  builtExamplesDir.listSync().forEach((example) {
    if (example is Directory) {
      copy(Directory(p.join(example.path, angularVersion.toString())),
          Directory('publish/examples/${p.basename(example.path)}'));
    }
  });
}

/// By default this cleans every temporary directory and build artifacts
/// Because `grinder` doesn't have negatable falgs yet, if you don't
/// want to delete something, **PASS THAT THING** as a flag
///
/// For example, if you **DON'T** want to delete the "publish" folder,
/// run `grind clean --publish`. It will delete everything else.
@Task('Clean temporary directories and build artifacts')
void clean() {
  // Ask grinder to add an negtable option
  TaskArgs args = context.invocation.arguments;

  // Cleans the "publish" directory
  bool cleanSite = !args.getFlag('publish');
  if (cleanSite && Directory('publish').existsSync()) {
    delete(Directory('publish'));
  }

  // Cleans the "$HOME/tmp" directory, used by some git stuffs
  bool cleanTmp = !args.getFlag('tmp');
  if (cleanTmp) {
    String path = p.join(
      // Please don't tell me you're on Android or iOS
      Platform.isWindows
          ? Platform.environment['UserProfile']
          : Platform.environment['HOME'],
      'tmp',
    );
    if (Directory(path).existsSync()) {
      delete(Directory(path));
    }
  }

  // Cleans the "src./asset-cache" directory
  bool cleanAssetCache = !args.getFlag('assetcache');
  if (cleanAssetCache && Directory('src/.asset-cache').existsSync()) {
    delete(Directory('src/.asset-cache'));
  }

  // TODO: also cleans the local tmp directory
  bool cleanLocalTmp = !args.getFlag('localtmp');
  if (cleanLocalTmp && Directory('tmp').existsSync()) {
    delete(Directory('tmp'));
  }
}
