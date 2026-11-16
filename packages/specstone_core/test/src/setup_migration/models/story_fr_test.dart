import 'package:specstone_core/src/setup_migration/models/story_fr.dart';
import 'package:test/test.dart';

StoryFr storyFr(int story, int fr) => StoryFr(story: story, fr: fr);

void main() {
  group('StoryFr', () {
    test('equals another StoryFr with the same story and fr', () {
      expect(storyFr(1, 2), storyFr(1, 2));
      expect(storyFr(1, 2), isNot(storyFr(1, 3)));
      expect(storyFr(1, 2), isNot(storyFr(2, 2)));
      expect(storyFr(1, 2).hashCode, storyFr(1, 2).hashCode);
    });
    test('a set holds one StoryFr per story and fr', () {
      expect({storyFr(1, 2), storyFr(1, 2), storyFr(1, 3)}, hasLength(2));
    });
  });
}
