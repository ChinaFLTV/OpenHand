/// 代理采集仅检查当前终端上下文，输出前移除 URL 凭据和查询参数。
const machineNetworkProxyEnvironment = r'''
env | awk '
BEGIN { FS="=" }
tolower($1) ~ /^(http_proxy|https_proxy|all_proxy|ftp_proxy|no_proxy)$/ {
  key=$1; value=substr($0,length(key)+2)
  gsub(/[^\/; ,]*@/,"***@",value); sub(/[?#].*$/,"",value)
  gsub(/[\t\r]/," ",value)
  printf "__OH_PROXY__\t终端环境\t%s\t%s\n",key,value
}' | head -c 8000
''';

const machineNetworkLinuxCounters = '''
cat /proc/net/dev
''';

const machineNetworkMacCounters = r'''
netstat -ibn | awk 'NR==1 {for(i=1;i<=NF;i++)offset[$i]=NF-i; next} function counter(key) {return key in offset ? $(NF-offset[key]) : -1} /<Link#/ {printf "%s: %.0f %.0f %.0f -1 0 0 0 0 %.0f %.0f %.0f -1 0 0 0 0\n",$1,counter("Ibytes"),counter("Ipkts"),counter("Ierrs"),counter("Obytes"),counter("Opkts"),counter("Oerrs")}'
''';

const machineNetworkWindowsCounters = r'''
var nets=rows("SELECT * FROM Win32_PerfRawData_Tcpip_NetworkInterface"),lines=[];
for(var i=0;i<nets.length;i++){var n=nets[i];if(n.BytesReceivedPersec==null || n.BytesSentPersec==null)continue;lines.push(encodeURIComponent(clean(n.Name))+": "+fixed(Number(n.BytesReceivedPersec))+" "+counter(n.PacketsReceivedPersec)+" "+counter(n.PacketsReceivedErrors)+" "+counter(n.PacketsReceivedDiscarded)+" 0 0 0 0 "+fixed(Number(n.BytesSentPersec))+" "+counter(n.PacketsSentPersec)+" "+counter(n.PacketsOutboundErrors)+" "+counter(n.PacketsOutboundDiscarded)+" 0 0 0 0");}emit("network",lines.join("\n"));
''';

const machineNetworkWindowsAdapters = r'''
var networkAdapters=rows("SELECT Index,Name,NetConnectionStatus,MACAddress FROM Win32_NetworkAdapter"),networkConfigs=rows("SELECT Index,IPAddress,DefaultIPGateway FROM Win32_NetworkAdapterConfiguration"),configsByIndex={},adapterLines=[];
function networkArray(value){if(value==null)return "—";try{return new VBArray(value).toArray().join(", ");}catch(e){return clean(value);}}
for(var i=0;i<networkConfigs.length;i++)configsByIndex[networkConfigs[i].Index]=networkConfigs[i];
for(var i=0;i<networkAdapters.length;i++){var a=networkAdapters[i],config=configsByIndex[a.Index];
adapterLines.push([clean(a.Name),a.NetConnectionStatus==null?"—":a.NetConnectionStatus==2?"已连接":a.NetConnectionStatus==0?"未连接":a.NetConnectionStatus==7?"未连接":String(a.NetConnectionStatus),clean(a.MACAddress)||"—","—",config?networkArray(config.IPAddress):"—",config?networkArray(config.DefaultIPGateway):"—"].join("\t"));}
emit("addresses",adapterLines.join("\n").substr(0,32000));
''';

const machineNetworkWindowsProxy = r'''
var proxyShell=new ActiveXObject("WScript.Shell"),proxyLines=[];
function proxyValue(scope,key,value){value=clean(value).replace(/[^\/; ,]*@/g,"***@").replace(/[?#].*$/,"");proxyLines.push("__OH_PROXY__\t"+scope+"\t"+key+"\t"+value);}
var proxyEnv=new Enumerator(proxyShell.Environment("PROCESS"));
for(;!proxyEnv.atEnd();proxyEnv.moveNext()){var entry=String(proxyEnv.item()),split=entry.indexOf("="),key=entry.substr(0,split);if(/^(http_proxy|https_proxy|all_proxy|ftp_proxy|no_proxy)$/i.test(key))proxyValue("终端环境",key,entry.substr(split+1));}
var proxyKeys=["ProxyEnable","ProxyServer","ProxyOverride","AutoConfigURL"];
for(var i=0;i<proxyKeys.length;i++){try{proxyValue("当前用户",proxyKeys[i],proxyShell.RegRead("HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\"+proxyKeys[i]));}catch(e){}}
proxyLines.push("__OH_PROXY_SCOPE__\tWinHTTP");
proxyLines.push(command("netsh winhttp show proxy",8000).replace(/[^\/; ,]*@/g,"***@").replace(/[?#][^\r\n]*/g,""));
emit("proxy",proxyLines.join("\n"));
''';

const machineNetworkWindowsFirewallStatus = r'''
var firewallLines=[];
try {var policy=new ActiveXObject("HNetCfg.FwPolicy2"),profiles=[1,2,4],profileNames=["域网络","专用网络","公用网络"];
for(var i=0;i<profiles.length;i++){var p=profiles[i];firewallLines.push(profileNames[i]+":\n状态: "+(policy.FirewallEnabled(p)?"启用":"禁用")+"\n当前配置: "+((policy.CurrentProfileTypes&p)!=0?"true":"false")+"\n默认入站: "+(policy.DefaultInboundAction(p)==0?"阻止":"允许")+"\n默认出站: "+(policy.DefaultOutboundAction(p)==0?"阻止":"允许"));}
emit("firewall_status",firewallLines.join("\n"));
} catch(e){emit("firewall_status","查询失败："+clean(e.message));}
''';
