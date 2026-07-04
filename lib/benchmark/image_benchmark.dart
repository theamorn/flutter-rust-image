import 'dart:typed_data';
import 'benchmark_result.dart';

abstract class ImageBenchmark {
  String get name;
  Future<BenchmarkResult> run(Uint8List source);
}
