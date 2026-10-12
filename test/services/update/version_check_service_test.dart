import 'package:camaleon_billboard/services/update/update_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Camaleon Billboard version check', () {
    test('uses product 36 for the single Android and Windows channel', () {
      expect(kCamaleonBillboardProductId, 36);
      expect(
        CamaleonVersionCheckService.versionCheckUrl(),
        'https://brian-pc.camaleonpos.com:8443/verscheck.php?a=vers&pid=36',
      );
    });

    test('parses release metadata and resolves a relative download path', () {
      const response = '''
        <vdata>
          <v0>
            <whatsnew>Billboard update</whatsnew>
            <version>1.2.3</version>
            <dldbuild>42</dldbuild>
            <dldpath>downloads/camaleon-billboard.apk</dldpath>
            <dlddate>2026-10-12</dlddate>
            <dldclog>Fixes</dldclog>
            <filesize>2048</filesize>
            <mandatory>true</mandatory>
            <sha256>abcdef</sha256>
          </v0>
        </vdata>
      ''';

      final release = CamaleonVersionCheckService.parseVersionXml(
        response,
      ).single;

      expect(release.version, '1.2.3');
      expect(release.build, 42);
      expect(release.fileSize, 2048);
      expect(release.mandatory, isTrue);
      expect(release.sha256, 'abcdef');
      expect(
        release.downloadUrl,
        'https://brian-pc.camaleonpos.com:8443/downloads/'
        'camaleon-billboard.apk',
      );
    });

    test('rejects the server NOTAVAILABLE response', () {
      expect(
        () => CamaleonVersionCheckService.parseVersionXml('ERROR:NOTAVAILABLE'),
        throwsFormatException,
      );
    });
  });

  test('Windows updater elevates silently and relaunches Billboard', () {
    final arguments = UpdateCheckService.windowsInstallerArguments(
      r"C:\Temp\Billboard's update.exe",
    );
    final command = arguments.last;

    expect(arguments.take(3), ['-NoProfile', '-NonInteractive', '-Command']);
    expect(command, contains("Billboard''s update.exe"));
    expect(command, contains("-Verb RunAs"));
    expect(command, contains("'/SILENT'"));
    expect(command, contains("'/CLOSEAPPLICATIONS'"));
    expect(
      command,
      contains(r'$env:ProgramFiles\CamaleonBillboard\camaleon_billboard.exe'),
    );
  });
}
