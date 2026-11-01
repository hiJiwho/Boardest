import 'package:flutter_test/flutter_test.dart';

import 'tier1_feature_coverage_test.dart' as tier1;
import 'tier2_boundary_corner_test.dart' as tier2;
import 'tier3_cross_feature_interaction_test.dart' as tier3;
import 'tier4_real_world_simulation_test.dart' as tier4;
import 'component_matrix_test.dart' as matrix;

void main() {
  group('Boardest Complete E2E Master Test Suite (4-Tier + 25-Component Matrix)', () {
    tier1.main();
    tier2.main();
    tier3.main();
    tier4.main();
    matrix.main();
  });
}
