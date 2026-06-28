import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/plugin_service/service/plugin_scanner_service.dart';

void main() {
  test('qdrant inspect metadata normalizes dirty docker inspect maps', () {
    final metadata = qdrantInspectMetadataFromDecoded(<Object?>[
      <Object?, Object?>{
        'Id': ' container-1 ',
        'Image': ' sha256:image ',
        'State': <Object?, Object?>{
          'Running': 'yes',
          'Status': ' running ',
          'StartedAt': '2026-06-28T00:00:00Z',
          'FinishedAt': '',
          'RestartCount': '2',
          'ExitCode': '-1',
        },
        'Config': <Object?, Object?>{
          'Image': 'qdrant/qdrant:v1.13.0',
          'Labels': <Object?, Object?>{'openhand.managed': '1'},
        },
        'NetworkSettings': <Object?, Object?>{
          'Ports': <Object?, Object?>{
            '6333/tcp': <Object?>[
              <Object?, Object?>{'HostIp': '127.0.0.1', 'HostPort': '6333'},
              <Object?, Object?>{'HostIp': '', 'HostPort': ''},
            ],
          },
        },
        'HostConfig': <Object?, Object?>{
          'RestartPolicy': <Object?, Object?>{
            'Name': 'unless-stopped',
            'MaximumRetryCount': '3',
          },
        },
        'Mounts': <Object?>[
          <Object?, Object?>{
            'Destination': '/qdrant/storage',
            'Source': ' /tmp/qdrant ',
          },
        ],
      },
    ]);

    expect(metadata, isNotNull);
    expect(metadata!['openhand_managed'], isTrue);
    expect(metadata['running'], isTrue);
    expect(metadata['container_id'], 'container-1');
    expect(metadata['container_status'], 'running');
    expect(metadata['restart_count'], 2);
    expect(metadata['exit_code'], isNull);
    expect(metadata['image'], 'qdrant/qdrant:v1.13.0');
    expect(metadata['ports'], '6333/tcp -> 127.0.0.1:6333');
    expect(metadata['restart_policy'], 'unless-stopped (3)');
    expect(metadata['data_directory'], '/tmp/qdrant');
    expect(metadata['rest_endpoint'], 'http://127.0.0.1:6333');
    expect(metadata['grpc_endpoint'], '127.0.0.1:6334');
  });

  test('qdrant inspect metadata rejects malformed inspect roots', () {
    expect(qdrantInspectMetadataFromDecoded(null), isNull);
    expect(qdrantInspectMetadataFromDecoded(<Object?>[]), isNull);
    expect(qdrantInspectMetadataFromDecoded(<Object?>['bad']), isNull);
  });
}
