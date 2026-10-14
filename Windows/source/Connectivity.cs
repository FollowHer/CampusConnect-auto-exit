using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace CampusConnect;

internal static class Connectivity
{
    private const SocketOptionName UnicastInterface = (SocketOptionName)31; // IP_UNICAST_IF / IPV6_UNICAST_IF (ws2ipdef.h)
    internal static readonly (string Url, string Body)[] Probes = [
        ("http://www.msftconnecttest.com/connecttest.txt", "Microsoft Connect Test"),
        ("https://www.apple.com/library/test/success.html", "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>")
    ];
    public static async Task<InternetStatus> CheckAsync(Guid? interfaceId)
    {
        // Fail closed when the campus WLAN interface is missing; another adapter must not validate it.
        if (interfaceId is null) return InternetStatus.Unavailable;
        try {
            var nic = NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n =>
                Guid.TryParse(n.Id, out var id) && id == interfaceId && n.OperationalStatus == OperationalStatus.Up);
            if (nic is null) return InternetStatus.Unavailable;
            using var handler = new SocketsHttpHandler { UseProxy = false, AllowAutoRedirect = false, UseCookies = false };
            handler.ConnectCallback = (context, cancellation) => ConnectThroughWifiAsync(nic, context.DnsEndPoint, cancellation);
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(8), MaxResponseContentBufferSize = 4096 };
            return await CheckWithClientAsync(client);
        } catch (NetworkInformationException) { return InternetStatus.Unavailable; }
    }
    internal static async Task<InternetStatus> CheckWithClientAsync(HttpClient client)
        => InternetEvidence.Combine(await Task.WhenAll(Probes.Select(probe => ProbeAsync(client, probe.Url, probe.Body))));

    private static async Task<ProbeOutcome> ProbeAsync(HttpClient client, string url, string expectedBody)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url + "?campus_probe=" + Guid.NewGuid().ToString("N"));
        request.Headers.TryAddWithoutValidation("Cache-Control", "no-cache, no-store");
        request.Headers.TryAddWithoutValidation("Pragma", "no-cache");
        try {
            using var response = await client.SendAsync(request);
            return InternetEvidence.Classify((int)response.StatusCode, await response.Content.ReadAsStringAsync(), expectedBody,
                response.RequestMessage?.RequestUri == request.RequestUri);
        } catch (HttpRequestException) { return ProbeOutcome.Unavailable; }
        catch (OperationCanceledException) { return ProbeOutcome.Unavailable; }
    }
    internal static async ValueTask<Stream> ConnectThroughWifiAsync(NetworkInterface nic, DnsEndPoint endpoint, CancellationToken cancellation)
    {
        var properties = nic.GetIPProperties();
        var addresses = await Dns.GetHostAddressesAsync(endpoint.Host, cancellation);
        foreach (var remote in addresses.OrderBy(a => a.AddressFamily == AddressFamily.InterNetwork ? 0 : 1)) {
            var local = properties.UnicastAddresses.FirstOrDefault(a => a.Address.AddressFamily == remote.AddressFamily &&
                !IPAddress.IsLoopback(a.Address) && !a.Address.IsIPv6LinkLocal)?.Address;
            if (local is null) continue;
            var socket = new Socket(remote.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
            try {
                if (remote.AddressFamily == AddressFamily.InterNetwork) {
                    var index = properties.GetIPv4Properties().Index;
                    // IP_UNICAST_IF takes the index in network byte order on Windows.
                    socket.SetSocketOption(SocketOptionLevel.IP, UnicastInterface, IPAddress.HostToNetworkOrder(index));
                } else {
                    socket.SetSocketOption(SocketOptionLevel.IPv6, UnicastInterface, properties.GetIPv6Properties().Index);
                }
                socket.Bind(new IPEndPoint(local, 0));
                using var attempt = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
                attempt.CancelAfter(TimeSpan.FromSeconds(3));
                await socket.ConnectAsync(new IPEndPoint(remote, endpoint.Port), attempt.Token);
                return new NetworkStream(socket, ownsSocket: true);
            } catch (Exception ex) when (ex is SocketException or OperationCanceledException or NetworkInformationException) {
                socket.Dispose();
                cancellation.ThrowIfCancellationRequested();
            }
        }
        throw new SocketException((int)SocketError.NetworkUnreachable);
    }
}
