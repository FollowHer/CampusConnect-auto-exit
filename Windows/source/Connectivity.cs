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
