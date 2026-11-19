import 'package:test/test.dart';

import 'helpers/timing_metric.dart';

void main() {
  test('timing metric is wall on CI or Windows, cpu otherwise', () {
    const ci = {'CI': 'true'};
    expect(metricFor(environment: ci, isWindows: false), TimingMetric.wall);
    expect(
      metricFor(environment: const {}, isWindows: true),
      TimingMetric.wall,
    );
    expect(metricFor(environment: ci, isWindows: true), TimingMetric.wall);
    expect(
      metricFor(environment: const {'HOME': '/h'}, isWindows: false),
      TimingMetric.cpu,
    );
  });
}
