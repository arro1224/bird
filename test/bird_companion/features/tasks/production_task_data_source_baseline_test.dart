import 'package:aves/bird_companion/features/tasks/presentation/production_task_experience_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production task source starts empty until B1 authority is loaded', () {
    const source = ProductionTaskExperienceDataSource();

    expect(source.initialTasks(), isEmpty);
    expect(source.executableTaskTypes(), isEmpty);
  });
}
