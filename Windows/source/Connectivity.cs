using System.Net.NetworkInformation;

namespace CampusConnect;

internal static class Connectivity
{
    public static async Task<InternetStatus> CheckAsync(Guid? interfaceId)
    {
        if (interfaceId is null) return InternetStatus.Unavailable;
        try {
            if (!NetworkInterface.GetAllNetworkInterfaces().Any(n =>
                Guid.TryParse(n.Id, out var id) && id == interfaceId && n.OperationalStatus == OperationalStatus.Up))
                return InternetStatus.Unavailable;
            // Like the system ping command, ICMP uses the current system route.
            using var ping = new Ping();
            return await CheckWithPingAsync(async () => (await ping.SendPingAsync("www.baidu.com", 3000)).Status);
        } catch (NetworkInformationException) { return InternetStatus.Unavailable; }
    }
    internal static async Task<InternetStatus> CheckWithPingAsync(Func<Task<IPStatus>> send, TimeSpan? timeout = null)
    {
        try {
            var status = await send().WaitAsync(timeout ?? TimeSpan.FromSeconds(6));
            return status == IPStatus.Success ? InternetStatus.Online : InternetStatus.Unavailable;
        } catch (Exception ex) when (ex is PingException or TimeoutException or OperationCanceledException or
                                    System.Net.Sockets.SocketException or InvalidOperationException) {
            return InternetStatus.Unavailable;
        }
    }
}

// Wired mode never calls WLAN APIs, so PCs without a wireless adapter can authenticate.
internal static class CampusNetwork
{
    internal static bool IsWiredInterface(NetworkInterfaceType type, OperationalStatus status)
        => status == OperationalStatus.Up && type is NetworkInterfaceType.Ethernet
            or NetworkInterfaceType.GigabitEthernet or NetworkInterfaceType.FastEthernetFx
            or NetworkInterfaceType.FastEthernetT;

    public static Guid? ReadWiredInterface()
    {
        try {
            return NetworkInterface.GetAllNetworkInterfaces()
                .Where(n => IsWiredInterface(n.NetworkInterfaceType, n.OperationalStatus)
                    && n.GetIPProperties().UnicastAddresses.Any(a => !System.Net.IPAddress.IsLoopback(a.Address)))
                .Select(n => Guid.TryParse(n.Id, out var id) ? (Guid?)id : null)
                .FirstOrDefault(id => id is not null);
        } catch (NetworkInformationException) { return null; }
    }
    public static async Task<bool> IsAvailableAsync(CampusProfile profile)
        => profile.IsWired ? ReadWiredInterface() is not null
            : profile.MatchesNetwork(await WifiService.ReadCurrentAsync(profile.Ssid), false);
    public static Task<Guid?> ReadInterfaceAsync(CampusProfile profile)
        => profile.IsWired ? Task.FromResult(ReadWiredInterface()) : WifiService.ReadInterfaceAsync(profile.Ssid);
}
