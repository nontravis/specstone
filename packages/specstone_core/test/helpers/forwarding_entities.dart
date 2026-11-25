// Each async member forwards the interface it implements, slow or not.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A `File` that hands every member to the file it wraps, so a test double
/// overrides only the members it changes.
class ForwardingFile implements File {
  const new(File inner) : _inner = inner;

  final File _inner;

  @override
  String get path => _inner.path;

  @override
  Uri get uri => _inner.uri;

  @override
  bool get isAbsolute => _inner.isAbsolute;

  @override
  File get absolute => _inner.absolute;

  @override
  Directory get parent => _inner.parent;

  @override
  Future<bool> exists() => _inner.exists();

  @override
  bool existsSync() => _inner.existsSync();

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) =>
      _inner.create(recursive: recursive, exclusive: exclusive);

  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      _inner.createSync(recursive: recursive, exclusive: exclusive);

  @override
  Future<File> rename(String newPath) => _inner.rename(newPath);

  @override
  File renameSync(String newPath) => _inner.renameSync(newPath);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _inner.delete(recursive: recursive);

  @override
  void deleteSync({bool recursive = false}) =>
      _inner.deleteSync(recursive: recursive);

  @override
  Future<File> copy(String newPath) => _inner.copy(newPath);

  @override
  File copySync(String newPath) => _inner.copySync(newPath);

  @override
  Future<int> length() => _inner.length();

  @override
  int lengthSync() => _inner.lengthSync();

  @override
  Future<String> resolveSymbolicLinks() => _inner.resolveSymbolicLinks();

  @override
  String resolveSymbolicLinksSync() => _inner.resolveSymbolicLinksSync();

  @override
  Future<FileStat> stat() => _inner.stat();

  @override
  FileStat statSync() => _inner.statSync();

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _inner.watch(events: events, recursive: recursive);

  @override
  Future<DateTime> lastAccessed() => _inner.lastAccessed();

  @override
  DateTime lastAccessedSync() => _inner.lastAccessedSync();

  @override
  Future<void> setLastAccessed(DateTime time) => _inner.setLastAccessed(time);

  @override
  void setLastAccessedSync(DateTime time) => _inner.setLastAccessedSync(time);

  @override
  Future<DateTime> lastModified() => _inner.lastModified();

  @override
  DateTime lastModifiedSync() => _inner.lastModifiedSync();

  @override
  Future<void> setLastModified(DateTime time) => _inner.setLastModified(time);

  @override
  void setLastModifiedSync(DateTime time) => _inner.setLastModifiedSync(time);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      _inner.open(mode: mode);

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _inner.openSync(mode: mode);

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _inner.openRead(start, end);

  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => _inner.openWrite(mode: mode, encoding: encoding);

  @override
  Future<Uint8List> readAsBytes() => _inner.readAsBytes();

  @override
  Uint8List readAsBytesSync() => _inner.readAsBytesSync();

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      _inner.readAsString(encoding: encoding);

  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      _inner.readAsStringSync(encoding: encoding);

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      _inner.readAsLines(encoding: encoding);

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      _inner.readAsLinesSync(encoding: encoding);

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _inner.writeAsBytes(bytes, mode: mode, flush: flush);

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _inner.writeAsBytesSync(bytes, mode: mode, flush: flush);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _inner.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => _inner.writeAsStringSync(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
}

/// A `Directory` that hands every member to the folder it wraps, so a test
/// double overrides only the members it changes.
class ForwardingDirectory implements Directory {
  const new(Directory inner) : _inner = inner;

  final Directory _inner;

  @override
  String get path => _inner.path;

  @override
  Uri get uri => _inner.uri;

  @override
  bool get isAbsolute => _inner.isAbsolute;

  @override
  Directory get absolute => _inner.absolute;

  @override
  Directory get parent => _inner.parent;

  @override
  Future<bool> exists() => _inner.exists();

  @override
  bool existsSync() => _inner.existsSync();

  @override
  Future<Directory> create({bool recursive = false}) =>
      _inner.create(recursive: recursive);

  @override
  void createSync({bool recursive = false}) =>
      _inner.createSync(recursive: recursive);

  @override
  Future<Directory> createTemp([String? prefix]) => _inner.createTemp(prefix);

  @override
  Directory createTempSync([String? prefix]) => _inner.createTempSync(prefix);

  @override
  Future<Directory> rename(String newPath) => _inner.rename(newPath);

  @override
  Directory renameSync(String newPath) => _inner.renameSync(newPath);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _inner.delete(recursive: recursive);

  @override
  void deleteSync({bool recursive = false}) =>
      _inner.deleteSync(recursive: recursive);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => _inner.list(recursive: recursive, followLinks: followLinks);

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => _inner.listSync(recursive: recursive, followLinks: followLinks);

  @override
  Future<String> resolveSymbolicLinks() => _inner.resolveSymbolicLinks();

  @override
  String resolveSymbolicLinksSync() => _inner.resolveSymbolicLinksSync();

  @override
  Future<FileStat> stat() => _inner.stat();

  @override
  FileStat statSync() => _inner.statSync();

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => _inner.watch(events: events, recursive: recursive);
}
