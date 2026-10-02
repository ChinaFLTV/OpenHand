import 'dart:convert';
import 'dart:io';

import 'support/flutter_widget_check.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'openhand-image-network-check-',
  );
  try {
    final certificate = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-keyout',
      '${directory.path}/key.pem',
      '-out',
      '${directory.path}/cert.pem',
      '-subj',
      '/CN=registry.test',
      '-addext',
      'subjectAltName=DNS:registry.test,DNS:cdn.test,DNS:hub.docker.com,IP:127.0.0.1',
    ]);
    if (certificate.exitCode != 0) throw StateError('测试证书生成失败。');
    await runFlutterWidgetCheck(
      root: File.fromUri(Platform.script).parent.parent,
      name: 'machine_image_network',
      source: _checks.replaceAll('CERT_DIRECTORY', jsonEncode(directory.path)),
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

const _checks = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_proxy_settings.dart';
import 'package:openhand/app/support/system_proxy.dart';
import 'package:openhand/features/machine_terminal/machine_containers.dart';
import 'package:openhand/features/machine_terminal/machine_image_download.dart';
import 'package:openhand/features/machine_terminal/machine_image_operations.dart';
import 'package:openhand/features/machine_terminal/machine_image_registry.dart';

const certDirectory = CERT_DIRECTORY;
final resolver = SystemProxyResolver.instance;
final trust=SecurityContext(withTrustedRoots:false)..setTrustedCertificates('$certDirectory/cert.pem');
HttpClient routedClient({Duration connectionTimeout=const Duration(seconds:15)})=>resolver.createRawHttpClient(context:trust,connectionTimeout:connectionTimeout,badCertificateCallback:(certificate,host,port)=>certificate.pem.trim()==File('$certDirectory/cert.pem').readAsStringSync().trim());

class Reader {
  Reader(this.socket) {
    stream = socket.asBroadcastStream(onCancel:(sub)=>sub.pause(),onListen:(sub)=>sub.resume());
    iterator=StreamIterator(stream);
  }
  final Socket socket;
  late final Stream<Uint8List> stream;
  late final StreamIterator<Uint8List> iterator;
  List<int> buffer=[];int offset=0;
  Future<List<int>> read(int size) async {
    final result=<int>[];
    while(result.length<size) {
      if(offset==buffer.length) {if(!await iterator.moveNext())throw const SocketException('测试连接已关闭');buffer=iterator.current;offset=0;}
      final count=(size-result.length).clamp(0,buffer.length-offset);result.addAll(buffer.getRange(offset,offset+count));offset+=count;
    }
    return result;
  }
}

class Fixture {
  late HttpServer origin,proxy;
  ServerSocket? socks;
  final sockets=<Socket>{};
  final requests=<({String path,String? authorization})>[];
  final tunnels=<String>[];
  bool private=false,corrupt=false,redirect=false,slow=false,badManifest=false;
  List<int> layer=[];
  late List<int> configuration,manifest,index;
  late String configDigest,manifestDigest,layerDigest;
  String get image=>'registry.test:${origin.port}/check/image:latest';
  String digest(List<int> bytes)=>'sha256:${sha256.convert(bytes)}';
  void configure({String architecture='arm64'}) {
    configuration=utf8.encode(jsonEncode({'architecture':architecture,'os':'linux','config':{},'rootfs':{'type':'layers','diff_ids':[if(layer.isNotEmpty)digest(gzip.decode(layer))]},'history':[if(layer.isNotEmpty){'created_by':'测试镜像'}]}));
    configDigest=digest(configuration);layerDigest=digest(layer);
    manifest=utf8.encode(jsonEncode({'schemaVersion':2,'mediaType':'application/vnd.oci.image.manifest.v1+json','config':{'mediaType':'application/vnd.oci.image.config.v1+json','digest':configDigest,'size':configuration.length},'layers':[if(layer.isNotEmpty){'mediaType':'application/vnd.oci.image.layer.v1.tar+gzip','digest':layerDigest,'size':layer.length}]}));
    manifestDigest=digest(manifest);
    index=utf8.encode(jsonEncode({'schemaVersion':2,'manifests':[
      {'digest':manifestDigest,'size':manifest.length,'platform':{'os':'linux','architecture':'invalid'}},
      {'digest':manifestDigest,'size':manifest.length,'platform':{'os':'linux','architecture':architecture}},
    ]}));
  }
  Future<void> start() async {
    final security=SecurityContext()..useCertificateChain('$certDirectory/cert.pem')..usePrivateKey('$certDirectory/key.pem');
    origin=await HttpServer.bindSecure(InternetAddress.loopbackIPv4,0,security);
    origin.listen((request)async {
      final response=request.response;final path=request.uri.path;final auth=request.headers.value(HttpHeaders.authorizationHeader);
      requests.add((path:path,authorization:auth));
      response.headers.contentType=ContentType.json;
      if(path=='/token') {
        if(private && auth!='Basic ${base64Encode(utf8.encode('tester:私有密码'))}') {response.statusCode=401;} else {response.write('{"token":"test-token"}');}
      } else if(path.startsWith('/v2/check/')) {
        if(auth!='Bearer test-token') {
          response.statusCode=401;response.headers.set(HttpHeaders.wwwAuthenticateHeader,'Bearer realm="https://registry.test:${origin.port}/token",service="test-registry"');
        } else if(path.endsWith('/manifests/latest')) {response.add(index);}
        else if(path.endsWith('/manifests/$manifestDigest')) {response.add(badManifest?utf8.encode(utf8.decode(manifest).replaceFirst('"schemaVersion":2','"schemaVersion":1')):manifest);}
        else if(path.endsWith('/blobs/$configDigest')) {response.add(configuration);}
        else if(path.endsWith('/blobs/$layerDigest')) {
          if(redirect){response.statusCode=307;response.headers.set(HttpHeaders.locationHeader,'https://cdn.test:${origin.port}/layer');}
          else if(slow) {await Future<void>.delayed(const Duration(seconds:2));try{response.add(layer);}catch(_) {}}
          else {response.add(corrupt?List<int>.filled(layer.length,1):layer);}
        } else {response.statusCode=404;}
      } else if(path=='/layer') {response.add(layer);}
      else if(path.endsWith('/tags')) {response.write('{"results":[{"name":"stable"}],"next":null}');}
      else if(path.endsWith('/tags/stable')) {response.write('{"name":"stable","images":[{"os":"linux","architecture":"arm64"}]}');}
      else if(path.endsWith('/repositories/nginx')) {response.write('{"name":"nginx","full_description":"说明"}');}
      else if(path=='/icon') {response.headers.contentType=ContentType('image','png');response.add([137,80,78,71]);}
      else {response.write('{"results":[{"repo_name":"nginx","star_count":42,"pull_count":1234,"is_official":true}]}');}
      try {await response.close();}catch(_) {}
    });
    proxy=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
    proxy.listen((request)async {
      if(request.headers.value(HttpHeaders.proxyAuthorizationHeader)!='Basic ${base64Encode(utf8.encode('代理用户:代理密码'))}') {
        request.response.statusCode=407;request.response.headers.set(HttpHeaders.proxyAuthenticateHeader,'Basic realm="proxy-check"');await request.response.close();return;
      }
      if(request.method!='CONNECT'){request.response.write('经过代理');await request.response.close();return;}
      tunnels.add('${request.uri}');
      final incoming=await request.response.detachSocket(writeHeaders:false);sockets.add(incoming);
      incoming.write('HTTP/1.1 200 Connection Established\r\n\r\n');await incoming.flush();
      final outgoing=await Socket.connect(InternetAddress.loopbackIPv4,origin.port);sockets.add(outgoing);
      unawaited(incoming.cast<List<int>>().pipe(outgoing).catchError((_){}));unawaited(outgoing.cast<List<int>>().pipe(incoming).catchError((_){}));
    });
    configure();httpRoute();
  }
  void httpRoute() => resolver.applyConfig(AppProxySettings.defaults().copyWith(mode:AppProxyMode.manual,host:'127.0.0.1',port:proxy.port,authEnabled:true,username:'代理用户',password:'代理密码'));
  Future<void> socksRoute({bool stall=false,int? targetPort}) async {
    socks=await ServerSocket.bind(InternetAddress.loopbackIPv4,0);
    socks!.listen((socket)async {
      sockets.add(socket);if(stall)return;
      final reader=Reader(socket);
      try {
        final greeting=await reader.read(2);expect(greeting[0],5);await reader.read(greeting[1]);socket.add([5,2]);await socket.flush();
        final header=await reader.read(2);final user=utf8.decode(await reader.read(header[1]));final length=(await reader.read(1)).single;final password=utf8.decode(await reader.read(length));
        expect(user,'代理用户');expect(password,'代理密码');socket.add([1,0]);await socket.flush();
        final command=await reader.read(4);expect(command[0],5);final count=command[3]==3?(await reader.read(1)).single:command[3]==1?4:16;
        await reader.read(count+2);await reader.iterator.cancel();
        final outgoing=await Socket.connect(InternetAddress.loopbackIPv4,targetPort??origin.port);sockets.add(outgoing);
        socket.add([5,0,0]);await socket.flush();socket.add([1,127,0,0,1,0,0]);await socket.flush();
        unawaited(reader.stream.cast<List<int>>().pipe(outgoing).catchError((_){}));unawaited(outgoing.cast<List<int>>().pipe(socket).catchError((_){}));
      }catch(_) {socket.destroy();}
    });
    resolver.applyConfig(AppProxySettings.defaults().copyWith(mode:AppProxyMode.manual,protocols:{AppProxyProtocol.socks},host:'127.0.0.1',port:socks!.port,authEnabled:true,username:'代理用户',password:'代理密码'));
  }
  Future<void> close() async {
    for(final socket in sockets)socket.destroy();
    await socks?.close();await proxy.close(force:true);await origin.close(force:true);resolver.applyConfig(AppProxySettings.defaults());
  }
  Future<T> download<T>(Future<T> Function(MachineImageArchive) consume,{bool Function()? cancelled,Duration timeout=const Duration(seconds:5),Future<MachineImageCredential?> Function(String)? credential}) => MachineImageDownload(clientFactory:routedClient).withArchive(
    image:image,os:'linux',architecture:'arm64',timeout:timeout,consume:consume,isCancelled:cancelled,credential:credential,
  );
}

void main() {
  late Fixture fixture;
  setUpAll(()async {SecurityContext.defaultContext.setTrustedCertificates('$certDirectory/cert.pem');
    await Directory('$certDirectory/layer').create();await File('$certDirectory/layer/hello').writeAsString('代理下载验证');
    final tar=await Process.run('tar',['-cf','$certDirectory/layer.tar','-C','$certDirectory/layer','hello']);expect(tar.exitCode,0);
  });
  setUp(()async{fixture=Fixture();await fixture.start();});
  tearDown(()async{await fixture.close();});

  test('搜索、详情、标签、图标经过带鉴权的全局代理，例外和无代理立即生效',()async {
    final registry=MachineImageRegistry(clientFactory:routedClient);
    try {
      expect((await registry.searchMetadata('nginx'))['library/nginx']!.pulls,1234);
      expect((await registry.tags('library/nginx')).tags,['stable']);
      expect((await registry.repositoryDetails('library/nginx'))['full_description'],'说明');
      expect((await registry.tagDetails('library/nginx','stable'))['images'],isNotEmpty);
      expect(await registry.icon('https://registry.test:${fixture.origin.port}/icon'),[137,80,78,71]);
      expect(fixture.tunnels,isNotEmpty);
      resolver.applyConfig(AppProxySettings.defaults().copyWith(mode:AppProxyMode.manual,host:'127.0.0.1',port:fixture.proxy.port,exceptions:['*.test']));
      expect(resolver.findProxyFor(Uri.parse(fixture.image.replaceFirst('registry.test','https://registry.test'))),'DIRECT');
      final count=fixture.tunnels.length;resolver.applyConfig(AppProxySettings.defaults().copyWith(mode:AppProxyMode.disabled));
      final client=routedClient();final response=await(await client.getUrl(Uri.parse('https://127.0.0.1:${fixture.origin.port}/direct'))).close();await response.drain<void>();client.close(force:true);
      expect(fixture.tunnels.length,count);
    }finally{registry.dispose();}
  });

  test('公开镜像不读取私有凭据，多架构选择、归档校验和关闭清理可靠',()async {
    final directory=Directory(certDirectory);await Directory('${directory.path}/layer').create();await File('${directory.path}/layer/hello').writeAsString('代理下载验证');
    final tar=await Process.run('tar',['-cf','${directory.path}/layer.tar','-C','${directory.path}/layer','hello']);expect(tar.exitCode,0);
    fixture.layer=gzip.encode(await File('${directory.path}/layer.tar').readAsBytes());fixture.configure();
    File? archive;
    await fixture.download((value)async {
      archive=value.file;expect(await value.file.exists(),isTrue);expect(value.configDigest,fixture.configDigest);
      final list=await Process.run('tar',['-tf',value.file.path]);expect(list.exitCode,0);expect('${list.stdout}',contains('manifest.json'));expect('${list.stdout}',contains('index.json'));
      final manifest=await Process.run('tar',['-xOf',value.file.path,'manifest.json']);expect((jsonDecode('${manifest.stdout}')as List).single['Layers'],['blobs/sha256/${fixture.layerDigest.substring(7)}']);
    },credential:(_)async=>throw StateError('公开镜像不应读取私有凭据'));
    expect(await archive!.exists(),isFalse);
  });

  test('私有凭据用于仓库鉴权，跨域分层重定向不携带仓库凭据',()async {
    fixture.private=true;fixture.layer=gzip.encode(List<int>.filled(512,0));fixture.redirect=true;fixture.configure();var reads=0;
    await fixture.download((_)async{},credential:(_)async {reads++;return(username:'tester',secret:'私有密码');});
    expect(reads,1);expect(fixture.requests.where((r)=>r.path=='/layer').single.authorization,isNull);
    expect(fixture.requests.where((r)=>r.path=='/token').any((r)=>r.authorization!=null),isTrue);
  });

  test('损坏分层、错误摘要和不匹配平台不会导入或绕过代理重试',()async {
    fixture.layer=gzip.encode(List<int>.filled(512,0));fixture.corrupt=true;fixture.configure();var imports=0;
    await expectLater(fixture.download((_)async{imports++;}),throwsA(isA<FormatException>()));expect(imports,0);
    fixture.corrupt=false;fixture.badManifest=true;await expectLater(fixture.download((_)async{imports++;}),throwsA(isA<FormatException>()));fixture.badManifest=false;
    await expectLater(MachineImageDownload(clientFactory:routedClient).withArchive(image:fixture.image,os:'windows',architecture:'arm64',timeout:const Duration(seconds:5),consume:(_)async{imports++;}),throwsA(isA<MachineContainerConfigException>()));expect(imports,0);
    for(final value in ['nginx;rm -rf /','--help','registry.test/image@sha256:bad'])expect(()=>MachineImageReference.parse(value),throwsA(isA<MachineContainerConfigException>()));
  });

  test('等待分层时取消和总超时会关闭连接且不导入',()async {
    fixture.layer=gzip.encode(List<int>.filled(512,0));fixture.slow=true;fixture.configure();var cancelled=false,imports=0;
    final work=fixture.download((_)async{imports++;},cancelled:()=>cancelled);
    await Future<void>.delayed(const Duration(milliseconds:100));cancelled=true;
    await expectLater(work,throwsA(anything));expect(imports,0);
    await expectLater(fixture.download((_)async{imports++;},timeout:const Duration(milliseconds:150)),throwsA(anything));expect(imports,0);
  });

  test('SOCKS 代理完成鉴权及 HTTP、HTTPS 请求，超时和强制关闭可取消连接',()async {
    await fixture.socksRoute();await fixture.download((_)async{});
    await fixture.socks!.close();fixture.socks=null;
    final plain=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
    plain.listen((request)async{request.response.write('SOCKS HTTP 已转发');await request.response.close();});
    final httpClient=routedClient();
    try {
      await fixture.socksRoute(targetPort:plain.port);
      final response=await(await httpClient.getUrl(Uri.parse('http://registry.test:${plain.port}/http'))).close();
      expect(await utf8.decoder.bind(response).join(),'SOCKS HTTP 已转发');
    }finally{httpClient.close(force:true);await plain.close(force:true);}
    await fixture.socks!.close();fixture.socks=null;await fixture.socksRoute(stall:true);
    final client=routedClient(connectionTimeout:const Duration(milliseconds:150));
    await expectLater(client.getUrl(Uri.parse('https://registry.test:${fixture.origin.port}/stalled')),throwsA(anything));client.close(force:true);
    final waiting=routedClient();final pending=waiting.getUrl(Uri.parse('https://registry.test:${fixture.origin.port}/stalled'));
    final assertion=expectLater(pending,throwsA(anything));await Future<void>.delayed(const Duration(milliseconds:30));waiting.close(force:true);await assertion.timeout(const Duration(seconds:1));
  });

  test('Docker、Podman、nerdctl 和 Windows 导入保留上下文并清理临时归档',()async {
    for(final runtime in [MachineContainerRuntime.docker,MachineContainerRuntime.podman,MachineContainerRuntime.containerd]) {
      for(final windows in [false,true]) {
        final commands=<String>[];var uploaded=false,cleaned=false;
        String decoded(String command) => windows && command.contains('-EncodedCommand')?String.fromCharCodes(base64Decode(command.split(' ').last).buffer.asUint16List()):command;
        Future<String> run(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled})async {
          final text=decoded(command);commands.add(text);
          if(text.contains("'info'"))return runtime==MachineContainerRuntime.podman?' {"host":{"os":"linux","arch":"aarch64"}}':'{"OSType":"linux","Architecture":"aarch64"}';
          if(text.contains('mktemp')||text.contains('GetTempPath'))return windows?r'C:\Temp\openhand-image-test12345':'/tmp/openhand-image-test12345';
          expect(uploaded,isTrue);expect(text,contains("'load' '--input'"));return '已导入';
        }
        final client=MachineContainerClient(runtime:runtime,contextName:'目标上下文',scope:'目标命名空间',windows:windows,run:(_)async=>throw StateError('不应调用默认通道'));
        final operations=MachineImageOperations(clientFactory:routedClient,run:run,upload:(file,directory,stopped,progress)async{expect(await file.exists(),isTrue);uploaded=true;progress(await file.length());},cleanup:(command)async{cleaned=true;expect(decoded(command),contains('openhand-image-test12345'));});
        final result=await operations.pull(client,fixture.image,timeout:const Duration(seconds:5));expect(result.output,'已导入');expect(cleaned,isTrue);
        expect(commands.any((c)=>c.contains("'pull'")),isFalse);
        if(runtime==MachineContainerRuntime.docker)expect(commands.last,contains("'--context' '目标上下文'"));
        if(runtime==MachineContainerRuntime.containerd)expect(commands.last,contains("'--namespace' '目标命名空间'"));
      }
    }
  });

  test('目标凭据及凭据助手不会进入进度输出，导入失败仍释放临时文件',()async {
    fixture.private=true;
    for(final helper in [false,true]) {
      var cleaned=false;final output=<String>[];
      Future<String> run(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled})async {
        if(command.contains("'info'"))return '{"OSType":"linux","Architecture":"aarch64"}';
        if(command.contains('__OH_REGISTRY_CONFIG__')) {
          expect(onOutput,isNull);
          return '__OH_REGISTRY_CONFIG__\n'+jsonEncode(helper?{'credsStore':'test'}:{'auths':{'registry.test:${fixture.origin.port}':{'auth':base64Encode(utf8.encode('tester:私有密码'))}}});
        }
        if(command.contains('docker-credential-test')){expect(onOutput,isNull);return '{"Username":"tester","Secret":"私有密码"}';}
        if(command.contains('mktemp'))return '/tmp/openhand-image-failure123';
        throw StateError('模拟导入失败');
      }
      final operations=MachineImageOperations(clientFactory:routedClient,run:run,upload:(file,directory,stopped,progress)async{},cleanup:(command)async{cleaned=true;});
      await expectLater(operations.pull(MachineContainerClient(runtime:MachineContainerRuntime.docker,run:(_)async=>''),fixture.image,timeout:const Duration(seconds:5),onOutput:output.add),throwsA(isA<StateError>()));
      expect(cleaned,isTrue);expect(output.join(),isNot(contains('私有密码')));
    }
    Future<String> failedCredentials(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled})async {
      if(command.contains("'info'"))return '{"OSType":"linux","Architecture":"aarch64"}';
      throw StateError('读取失败，配置含私有密码');
    }
    final operations=MachineImageOperations(clientFactory:routedClient,run:failedCredentials,
      upload:(file,directory,stopped,progress)async=>throw StateError('不应上传'),cleanup:(_)async{});
    await expectLater(operations.pull(MachineContainerClient(runtime:MachineContainerRuntime.docker,run:(_)async=>''),fixture.image,timeout:const Duration(seconds:5)),
      throwsA(isA<MachineContainerConfigException>().having((error)=>'$error','错误详情',isNot(contains('私有密码')))));
  });

  test('实际 Docker 可加载代理下载归档并保持镜像配置与分层',()async {
    if(Platform.environment['IMAGE_IMPORT_REAL']!='1')return;
    final info=await Process.run('docker',['info','--format','{{.Architecture}}']);expect(info.exitCode,0);
    final arch='${info.stdout}'.trim();fixture.layer=gzip.encode(await File('$certDirectory/layer.tar').readAsBytes());fixture.configure(architecture:arch=='aarch64'?'arm64':arch=='x86_64'?'amd64':arch);
    try {
      await MachineImageDownload(clientFactory:routedClient).withArchive(image:fixture.image,os:'linux',architecture:arch=='aarch64'?'arm64':arch=='x86_64'?'amd64':arch,timeout:const Duration(seconds:10),consume:(archive)async {
        final loaded=await Process.run('docker',['load','--input',archive.file.path]);expect(loaded.exitCode,0,reason:'${loaded.stderr}');
        final inspect=await Process.run('docker',['image','inspect','--format','{{.Id}}',archive.reference]);expect(inspect.exitCode,0);expect('${inspect.stdout}'.trim(),anyOf(fixture.configDigest,fixture.manifestDigest));
        final layers=await Process.run('docker',['image','inspect','--format','{{json .RootFS.Layers}}',archive.reference]);expect(jsonDecode('${layers.stdout}'),[fixture.digest(gzip.decode(fixture.layer))]);
      });
      Future<String> run(String command,{required Duration timeout,void Function(String)? onOutput,bool Function()? isCancelled})async {
        final result=await Process.run('/bin/sh',['-c',command]).timeout(timeout);
        if(result.exitCode!=0)throw StateError('${result.stderr}');
        onOutput?.call('${result.stdout}');return '${result.stdout}';
      }
      final operations=MachineImageOperations(clientFactory:routedClient,run:run,
        upload:(file,directory,stopped,progress)async{await file.copy('$directory/image.tar');},
        cleanup:(command)async{await run(command,timeout:const Duration(seconds:5));});
      final imported=await operations.pull(MachineContainerClient(runtime:MachineContainerRuntime.docker,run:(_)async=>''),
        fixture.image.split(':latest').first+'@'+fixture.manifestDigest,timeout:const Duration(seconds:15));
      expect(imported.image,anyOf(fixture.configDigest,fixture.manifestDigest));
      final inspect=await Process.run('docker',['image','inspect','--format','{{.Id}}',imported.image]);
      expect(inspect.exitCode,0);expect('${inspect.stdout}'.trim(),imported.image);
    }finally {await Process.run('docker',['image','rm',fixture.image]);}
  });
}
''';
