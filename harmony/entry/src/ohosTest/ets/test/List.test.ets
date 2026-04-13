import localUnitTest from './LocalUnit.test';
import kwMusicUrlTest from './KwMusicUrl.test';
import abilityTest from './Ability.test';

export default function testsuite() {
  localUnitTest();
  kwMusicUrlTest();
  abilityTest();
}
