part of 'machine_maintenance_localizations.dart';

final _networkCounterWhitespace = RegExp(r'\s+');
final _networkCounterWords = RegExp(r'\b[a-z]+\b');
final _networkCounterNumbers = RegExp(r'\b\d+\b');

/// 系统统计保留原始标识用于核对；仅转换已知语义，不猜测未知计数器。
String? maintenanceNetworkCounterLabel(BuildContext context, String field) {
  final l = AppLocalizations.of(context)!;
  var key = field.trim().toLowerCase().replaceAll(
    _networkCounterWhitespace,
    ' ',
  );
  const plurals = {
    'packets': 'packet',
    'bytes': 'byte',
    'segments': 'segment',
    'datagrams': 'datagram',
    'connections': 'connection',
    'requests': 'request',
    'accepts': 'accept',
    'attempts': 'attempt',
    'drops': 'drop',
    'acks': 'ack',
    'sockets': 'socket',
    'messages': 'message',
    'responses': 'response',
    'fragments': 'fragment',
    'timeouts': 'timeout',
    'probes': 'probe',
    'resends': 'resend',
  };
  key = key
      .replaceAll('(s)', '')
      .replaceAllMapped(_networkCounterWords, (m) => plurals[m[0]] ?? m[0]!);
  const aliases = {
    'window probe': 'window probe packet',
    'connection established (including accept)':
        'connection established (including accepts)',
    'destination unreachable': 'unreach',
    "error not generated 'cuz old message was icmp":
        'error not generated because old message was icmp error or so',
    'with bad checksum': 'bad checksum',
    'segment received': 'insegs',
    'segment sent': 'outsegs',
    'segment retransmitted': 'retranssegs',
    'active opens': 'activeopens',
    'passive opens': 'passiveopens',
    'failed connection attempt': 'attemptfails',
    'reset connection': 'estabresets',
    'current connection': 'currestab',
    'datagram sent': 'outdatagrams',
  };
  key = aliases[key] ?? key;
  final values = <String>[];
  key = key.replaceAllMapped(_networkCounterNumbers, (match) {
    final index = values.length;
    values.add(match[0]!);
    return '{v$index}';
  });
  return switch (key) {
    "packet sent" => l.maintenanceNetCounterPacketsSent,
    "packet received" => l.maintenanceNetCounterPacketsReceived,
    "data packet ({v0} byte)" when values.length == 1 =>
      l.maintenanceNetCounterDataPackets(values[0]),
    "data packet ({v0} byte) retransmitted" when values.length == 1 =>
      l.maintenanceNetCounterRetransmittedData(values[0]),
    "resend initiated by mtu discovery" => l.maintenanceNetCounterMtuResend,
    "ack-only packet ({v0} delayed)" when values.length == 1 =>
      l.maintenanceNetCounterAckOnly(values[0]),
    "urg only packet" => l.maintenanceNetCounterUrgOnly,
    "window probe packet" => l.maintenanceNetCounterWindowProbe,
    "window update packet" => l.maintenanceNetCounterWindowUpdate,
    "control packet" => l.maintenanceNetCounterControlPacket,
    "data packet sent after flow control" =>
      l.maintenanceNetCounterAfterFlowControl,
    "challenge ack sent due to unexpected syn" =>
      l.maintenanceNetCounterChallengeSyn,
    "challenge ack sent due to unexpected rst" =>
      l.maintenanceNetCounterChallengeRst,
    "checksummed in software" => l.maintenanceNetCounterSoftwareChecksum,
    "segment ({v0} byte) over ipv4" when values.length == 1 =>
      l.maintenanceNetCounterIpv4Segments(values[0]),
    "segment ({v0} byte) over ipv6" when values.length == 1 =>
      l.maintenanceNetCounterIpv6Segments(values[0]),
    "ack (for {v0} byte)" when values.length == 1 =>
      l.maintenanceNetCounterAcknowledgments(values[0]),
    "duplicate ack" => l.maintenanceNetCounterDuplicateAck,
    "ack for unsent data" => l.maintenanceNetCounterUnsentAck,
    "packet ({v0} byte) received in-sequence" when values.length == 1 =>
      l.maintenanceNetCounterInSequence(values[0]),
    "completely duplicate packet ({v0} byte)" when values.length == 1 =>
      l.maintenanceNetCounterDuplicatePacket(values[0]),
    "old duplicate packet" => l.maintenanceNetCounterOldDuplicate,
    "received packet dropped due to low memory" =>
      l.maintenanceNetCounterReceiveNoMemory,
    "packet with some dup. data ({v0} byte duped)" when values.length == 1 =>
      l.maintenanceNetCounterPartialDuplicate(values[0]),
    "out-of-order packet ({v0} byte)" when values.length == 1 =>
      l.maintenanceNetCounterOutOfOrder(values[0]),
    "packet ({v0} byte) of data after window" when values.length == 1 =>
      l.maintenanceNetCounterBeyondWindow(values[0]),
    "packet recovered after loss" => l.maintenanceNetCounterRecoveredLoss,
    "packet received after close" => l.maintenanceNetCounterAfterClose,
    "bad reset" => l.maintenanceNetCounterBadReset,
    "discarded for bad checksum" => l.maintenanceNetCounterBadChecksumDiscard,
    "bad checksum" => l.maintenanceNetCounterBadChecksum,
    "discarded for bad header offset field" =>
      l.maintenanceNetCounterBadHeaderOffset,
    "discarded because packet too short" => l.maintenanceNetCounterTooShort,
    "connection request" => l.maintenanceNetCounterConnectionRequests,
    "connection accept" => l.maintenanceNetCounterConnectionAccepts,
    "bad connection attempt" => l.maintenanceNetCounterBadConnection,
    "listen queue overflow" => l.maintenanceNetCounterListenOverflow,
    "connection established (including accepts)" =>
      l.maintenanceNetCounterEstablished,
    "connection closed (including {v0} drop)" when values.length == 1 =>
      l.maintenanceNetCounterClosedConnections(values[0]),
    "retransmit timeout" => l.maintenanceNetCounterRetransmitTimeout,
    "persist timeout" => l.maintenanceNetCounterPersistTimeout,
    "keepalive timeout" => l.maintenanceNetCounterKeepaliveTimeout,
    "keepalive probe sent" => l.maintenanceNetCounterKeepaliveProbe,
    "calls to icmp_error" => l.maintenanceNetCounterIcmpError,
    "error not generated because old message was icmp error or so" =>
      l.maintenanceNetCounterIcmpSuppressed,
    "error not generated because rate limitation" =>
      l.maintenanceNetCounterIcmpRateLimit,
    "no route" => l.maintenanceNetCounterNoRoute,
    "administratively prohibited" => l.maintenanceNetCounterAdminProhibited,
    "beyond scope" => l.maintenanceNetCounterBeyondScope,
    "address unreachable" => l.maintenanceNetCounterAddressUnreachable,
    "port unreachable" => l.maintenanceNetCounterPortUnreachable,
    "packet too big" => l.maintenanceNetCounterPacketTooBig,
    "time exceed transit" => l.maintenanceNetCounterTransitExceeded,
    "time exceed reassembly" => l.maintenanceNetCounterReassemblyExceeded,
    "erroneous header field" => l.maintenanceNetCounterHeaderError,
    "unrecognized next header" => l.maintenanceNetCounterUnknownNextHeader,
    "unrecognized option" => l.maintenanceNetCounterUnknownOption,
    "redirect" => l.maintenanceNetCounterRedirect,
    "unknown" => l.maintenanceNetCounterUnknown,
    "unreach" => l.maintenanceNetCounterUnreachable,
    "echo" => l.maintenanceNetCounterEcho,
    "echo reply" => l.maintenanceNetCounterEchoReply,
    "router solicitation" => l.maintenanceNetCounterRouterSolicit,
    "router advertisement" => l.maintenanceNetCounterRouterAdvert,
    "neighbor solicitation" => l.maintenanceNetCounterNeighborSolicit,
    "neighbor advertisement" => l.maintenanceNetCounterNeighborAdvert,
    "multicast listener query" => l.maintenanceNetCounterMulticastQuery,
    "mldv2 listener report" => l.maintenanceNetCounterMldReport,
    "message with bad code fields" => l.maintenanceNetCounterBadCode,
    "message < minimum length" => l.maintenanceNetCounterShortMessage,
    "message with bad length" => l.maintenanceNetCounterBadLength,
    "message response generated" => l.maintenanceNetCounterResponses,
    "datagram received" => l.maintenanceNetCounterDatagramsReceived,
    "datagram output" => l.maintenanceNetCounterDatagramsSent,
    "with incomplete header" => l.maintenanceNetCounterIncompleteHeader,
    "with bad data length field" => l.maintenanceNetCounterBadDataLength,
    "with no checksum" => l.maintenanceNetCounterNoChecksum,
    "dropped due to no socket" => l.maintenanceNetCounterNoSocket,
    "dropped due to full socket buffers" => l.maintenanceNetCounterFullSocket,
    "delivered" => l.maintenanceNetCounterDelivered,
    "datagram ({v0} byte) over ipv4" when values.length == 1 =>
      l.maintenanceNetCounterIpv4Datagrams(values[0]),
    "datagram ({v0} byte) over ipv6" when values.length == 1 =>
      l.maintenanceNetCounterIpv6Datagrams(values[0]),
    "total packet received" => l.maintenanceNetCounterTotalReceived,
    "fragment received" => l.maintenanceNetCounterFragmentsReceived,
    "reassembled ok" => l.maintenanceNetCounterReassembled,
    "packet for this host" => l.maintenanceNetCounterForHost,
    "packet sent from this host" => l.maintenanceNetCounterFromHost,
    "packet forwarded" => l.maintenanceNetCounterForwarded,
    "packet not forwardable" => l.maintenanceNetCounterNotForwardable,
    "redirect sent" => l.maintenanceNetCounterRedirectSent,
    "open tcp socket" => l.maintenanceNetCounterOpenTcp,
    "open raw ip socket" => l.maintenanceNetCounterOpenRaw,
    "open local socket" => l.maintenanceNetCounterOpenLocal,
    "activeopens" => l.maintenanceNetCounterActiveOpens,
    "passiveopens" => l.maintenanceNetCounterPassiveOpens,
    "attemptfails" => l.maintenanceNetCounterAttemptFails,
    "estabresets" => l.maintenanceNetCounterEstablishedResets,
    "currestab" => l.maintenanceNetCounterCurrentEstablished,
    "insegs" => l.maintenanceNetCounterInSegments,
    "outsegs" => l.maintenanceNetCounterOutSegments,
    "retranssegs" => l.maintenanceNetCounterRetransSegments,
    "inerrs" => l.maintenanceNetCounterInputErrors,
    "outresets" => l.maintenanceNetCounterOutputResets,
    "inreceives" => l.maintenanceNetCounterInputPackets,
    "indelivers" => l.maintenanceNetCounterInputDeliveries,
    "outrequests" => l.maintenanceNetCounterOutputRequests,
    "indiscards" => l.maintenanceNetCounterInputDiscards,
    "outdiscards" => l.maintenanceNetCounterOutputDiscards,
    "inunknownprotos" => l.maintenanceNetCounterUnknownProtocols,
    "inhdrerrors" => l.maintenanceNetCounterInputHeaderErrors,
    "inaddrerrors" => l.maintenanceNetCounterInputAddressErrors,
    "outnoroutes" => l.maintenanceNetCounterOutputNoRoutes,
    "indatagrams" => l.maintenanceNetCounterInputDatagrams,
    "outdatagrams" => l.maintenanceNetCounterOutputDatagrams,
    "noports" => l.maintenanceNetCounterNoPorts,
    "rcvbuferrors" => l.maintenanceNetCounterReceiveBufferErrors,
    "sndbuferrors" => l.maintenanceNetCounterSendBufferErrors,
    "incsumerrors" => l.maintenanceNetCounterInputChecksumErrors,
    "reasmreqds" => l.maintenanceNetCounterReassemblyRequests,
    "reasmoks" => l.maintenanceNetCounterReassemblyOk,
    "reasmfails" => l.maintenanceNetCounterReassemblyFails,
    "fragoks" => l.maintenanceNetCounterFragmentOk,
    "fragfails" => l.maintenanceNetCounterFragmentFails,
    "fragcreates" => l.maintenanceNetCounterFragmentsCreated,
    "listendrops" => l.maintenanceNetCounterListenDrops,
    "listenoverflows" => l.maintenanceNetCounterListenOverflows,
    "inmsgs" => l.maintenanceNetCounterInputMessages,
    "outmsgs" => l.maintenanceNetCounterOutputMessages,
    "inuse" => l.maintenanceNetCounterInUse,
    "orphan" => l.maintenanceNetCounterOrphan,
    "tw" => l.maintenanceNetCounterTimeWait,
    "alloc" => l.maintenanceNetCounterAllocated,
    "mem" => l.maintenanceNetCounterMemoryPages,
    _ => null,
  };
}

String maintenanceNetworkGroupLabel(
  BuildContext context,
  String group,
  int index,
) {
  final l = AppLocalizations.of(context)!;
  return group
      .split(' / ')
      .map((part) {
        final key = part.toLowerCase().replaceFirst(
          RegExp(r' statistics.*$'),
          '',
        );
        final protocol = const {
          'tcp': 'TCP',
          'udp': 'UDP',
          'ip': 'IPv4',
          'ip6': 'IPv6',
          'ipv4': 'IPv4',
          'ipv6': 'IPv6',
          'icmp': 'ICMP',
          'icmp6': 'ICMPv6',
          'icmpv6': 'ICMPv6',
          'igmp': 'IGMP',
          'ipsec': 'IPsec',
          'ipsec6': 'IPsec / IPv6',
          'arp': 'ARP',
          'mptcp': 'MPTCP',
          'rip6': 'RIPng',
          'tcpext': 'TCP Ext',
          'ipext': 'IP Ext',
          'udplite': 'UDP-Lite',
          'tcp6': 'TCP / IPv6',
          'udp6': 'UDP / IPv6',
          'udplite6': 'UDP-Lite / IPv6',
          'raw': 'Raw IP',
          'raw6': 'Raw IPv6',
          'frag': 'IP Frag',
          'frag6': 'IPv6 Frag',
          'icmpmsg': 'ICMP',
          'local (unix)': 'UNIX',
          'pfkey': 'PF_KEY',
          'vsock': 'VSOCK',
          'vsock_private': 'VSOCK',
        }[key];
        if (protocol != null) {
          return l.maintenanceReadoutProtocolStats(protocol);
        }
        return switch (key) {
          'kevt' => l.maintenanceReadoutKernelEvents,
          'kctl' => l.maintenanceReadoutKernelControl,
          'nstat' => l.maintenanceReadoutNetworkMonitoring,
          'xbkidle' => l.maintenanceReadoutBackgroundSockets,
          'net_api' => l.maintenanceReadoutNetworkApi,
          'if_ports_used' => l.maintenanceReadoutWakePorts,
          'droptap' => l.maintenanceReadoutDropReasons,
          'local ports offload' => l.maintenanceReadoutPortOffload,
          'mbuf statistics' => l.maintenanceReadoutMbuf,
          'two or more mbuf' => l.maintenanceReadoutMultiMbuf,
          'input histogram' => l.maintenanceReadoutInputHistogram,
          'output histogram' => l.maintenanceReadoutOutputHistogram,
          'histogram of error messages to be generated' =>
            l.maintenanceReadoutErrorHistogram,
          '统计' => l.maintenanceNetworkProtocolStats,
          _ => l.maintenanceReadoutUnknownGroup('$index'),
        };
      })
      .join(' › ');
}
