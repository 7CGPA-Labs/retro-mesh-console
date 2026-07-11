import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

final cores = [
  'fbneo',
  'flycast',
  'mame2003_plus',
  'melonds',
  'pcsx_rearmed',
  'gambatte',
  'mgba',
  'dosbox_pure',
  'bluemsx',
  'fceumm',
  'genesis_plus_gx',
  'snes9x',
];

const androidBaseUrl = 'https://buildbot.libretro.com/nightly/android/latest/arm64-v8a';
const iosBaseUrl = 'https://buildbot.libretro.com/nightly/apple/ios-arm64/latest';

Future<void> main(List<String> args) async {
  if (args.isEmpty || (args[0] != 'android' && args[0] != 'ios')) {
    print('Usage: dart run scripts/download_cores.dart [android|ios]');
    exit(1);
  }

  String platform = args[0];
  String baseUrl = platform == 'android' ? androidBaseUrl : iosBaseUrl;
  String ext = platform == 'android' ? '_libretro_android.so' : '_libretro_ios.dylib';
  
  // Resolve the root directory regardless of whether this is run from root or from ios/
  String rootPath = Directory.current.path.endsWith('ios') 
      ? Directory.current.parent.path 
      : Directory.current.path;
  Directory coresDir = Directory(p.join(rootPath, 'assets/cores'));
  
  if (!coresDir.existsSync()) {
    coresDir.createSync(recursive: true);
  }

  // Generate an empty .gitkeep so Flutter asset bundler doesn't crash if folder is empty initially
  File(p.join(coresDir.path, '.gitkeep')).writeAsStringSync('');

  final httpClient = HttpClient();
  
  for (String core in cores) {
    String filename = '$core$ext';
    String zipFilename = '$filename.zip';
    String url = '$baseUrl/$zipFilename';
    File outputFile = File(p.join(coresDir.path, filename));

    if (outputFile.existsSync()) {
      print('Skipping $core (already exists)');
      continue;
    }

    print('Downloading $core from $url ...');
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        print('Error downloading $core: HTTP ${response.statusCode}');
        continue;
      }
      
      // Download to temp file
      File tempZip = File(p.join(coresDir.path, zipFilename));
      var fileStream = tempZip.openWrite();
      await response.pipe(fileStream);
      
      print('Extracting $core ...');
      // Extract
      final bytes = tempZip.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final file in archive) {
        if (file.isFile && file.name.endsWith(ext)) {
          final data = file.content as List<int>;
          File(p.join(coresDir.path, file.name)).writeAsBytesSync(data);
        }
      }
      
      // Cleanup zip
      tempZip.deleteSync();
      print('Successfully installed $core');
      
    } catch (e) {
      print('Failed to download/extract $core: $e');
    }
  }
  
  httpClient.close(force: true);
  print('Core downloading process complete.');
  exit(0);
}
