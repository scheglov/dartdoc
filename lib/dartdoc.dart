// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dartdoc;

import 'dart:io';
import 'dart:async';

import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source_io.dart';

import 'package:path/path.dart' as path;

import 'generator.dart';
import 'src/html_generator.dart';
import 'src/io_utils.dart';
import 'src/model.dart';
import 'src/model_utils.dart';

const String NAME = 'dartdoc';

// Update when pubspec version changes
const String VERSION = '0.0.1+5';

/// Initialize and setup the generators
List<Generator> initGenerators(
    String url, String headerFilePath, String footerFilePath) {
  return [new HtmlGenerator(url, headerFilePath, footerFilePath)];
}

/// Generates Dart documentation for all public Dart libraries in the given
/// directory.
class DartDoc {
  final List<String> _excludes;
  final Directory _rootDir;
  final Directory _sdkDir;
  Directory outputDir;
  final bool sdkDocs;
  final Set<LibraryElement> libraryElementList = new Set();
  final Set<Library> libraryList = new Set();
  final List<Generator> _generators;
  final String sdkReadmePath;

  Stopwatch stopwatch;

  DartDoc(this._rootDir, this._excludes, this._sdkDir, this._generators,
      this.outputDir, {this.sdkDocs: false, this.sdkReadmePath});

  /// Generate the documentation
  Future generateDocs() async {
    stopwatch = new Stopwatch();
    stopwatch.start();

    var files = sdkDocs ? [] : findFilesToDocumentInPackage(_rootDir.path);

    Package package;

    _parseLibraries(files);

    if (sdkDocs) {
      // remove excluded libraries
      _excludes.forEach((pattern) =>
          libraryElementList.removeWhere((l) => l.name.startsWith(pattern)));
      libraryElementList
        ..removeWhere(
            (LibraryElement library) => _excludes.contains(library.name));
      package = new Package.fromLibraryElement(libraryElementList, _rootDir.path,
          sdkVersion: _getSdkVersion(),
          isSdk: sdkDocs,
          readmeLoc: sdkReadmePath);
    } else {
      package = new Package.fromLibrary(libraryList, _rootDir.path,
          sdkVersion: _getSdkVersion(),
          isSdk: sdkDocs,
          readmeLoc: sdkReadmePath);
    }

    // create the out directory
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    for (var generator in _generators) {
      await generator.generate(package, outputDir);
    }

    double seconds = stopwatch.elapsedMilliseconds / 1000.0;
    print('');
    var length = libraryElementList.isNotEmpty ? libraryElementList.length : libraryList.length;
    print(
        "Documented ${length} librar${length == 1 ? 'y' : 'ies'} in ${seconds.toStringAsFixed(1)} seconds.");
  }

  void _parseLibraries(List<String> files) {
    DartSdk sdk = new DirectoryBasedDartSdk(new JavaFile(_sdkDir.path));
    List<UriResolver> resolvers = [
      new DartUriResolver(sdk),
      new FileUriResolver()
    ];
    JavaFile packagesDir =
        new JavaFile.relative(new JavaFile(_rootDir.path), 'packages');
    if (packagesDir.exists()) {
      resolvers.add(new PackageUriResolver([packagesDir]));
    }
    SourceFactory sourceFactory =
        new SourceFactory(/*contentCache,*/ resolvers);

    var options = new AnalysisOptionsImpl()..analyzeFunctionBodies = false;

    AnalysisContext context = AnalysisEngine.instance.createAnalysisContext()
      ..analysisOptions = options
      ..sourceFactory = sourceFactory;

    if (sdkDocs) {
      var sdkLibs = getSdkLibrariesToDocument(sdk, context);
      libraryElementList.addAll(sdkLibs);
    } else {
      files.forEach((String filePath) {
        print('parsing ${filePath}...');
        Source source = new FileBasedSource.con1(new JavaFile(filePath));
        if (context.computeKindOf(source) == SourceKind.LIBRARY) {
          LibraryElement library = context.computeLibraryElement(source);
          if (!_isExcluded(library)) {
            var sourceString = new File(filePath).readAsStringSync();
            libraryList.add(new Library(library, null, sourceString));
          }
        }
      });
    }
    double seconds = stopwatch.elapsedMilliseconds / 1000.0;
    var length = libraryElementList.isNotEmpty ? libraryElementList.length : libraryList.length;
    print(
        "\nParsed ${length} " "librar${length == 1 ? 'y' : 'ies'} in " "${seconds.toStringAsFixed(1)} seconds.\n");
  }

  String _getSdkVersion() {
    File versionFile = new File(path.join(_sdkDir.path, 'version'));
    return versionFile.readAsStringSync();
  }

  bool _isExcluded(LibraryElement library) {
    return _excludes.any((pattern) => library.name.startsWith(pattern)) ||
        _excludes.contains(library.name);
  }
}
