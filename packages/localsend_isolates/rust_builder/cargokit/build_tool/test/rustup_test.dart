import 'package:build_tool/src/rustup.dart';
import 'package:build_tool/src/util.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() => testRunCommandOverride = null);

  test('recognizes pinned releases and trims Windows line endings', () {
    final queried = <String>[];
    testRunCommandOverride = (args) {
      expect(args.executable, 'rustup');
      if (args.arguments.join(' ') == 'toolchain list') {
        return TestRunCommandResult(
          stdout: '1.97.1-x86_64-pc-windows-msvc (active, default)\r\n'
              'stable-x86_64-pc-windows-msvc\r\n'
              'custom-compiler\r\n',
        );
      }
      expect(args.arguments.take(3), ['target', 'list', '--toolchain']);
      queried.add(args.arguments[3]);
      return TestRunCommandResult(stdout: 'x86_64-pc-windows-msvc\r\n');
    };

    final rustup = Rustup();
    expect(rustup.installedTargets('1.97.1'), ['x86_64-pc-windows-msvc']);
    expect(rustup.installedTargets('stable'), ['x86_64-pc-windows-msvc']);
    expect(rustup.installedTargets('custom-compiler'), isNull);
    expect(queried, [
      '1.97.1-x86_64-pc-windows-msvc',
      'stable-x86_64-pc-windows-msvc',
    ]);
  });
}
