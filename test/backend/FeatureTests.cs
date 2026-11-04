using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.AspNetCore.Http.Connections;

public class FeatureTests
{
    private sealed class ApiFactory : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.UseSetting("ConnectionStrings:DefaultConnection",
                $"Data Source={Path.Combine(Path.GetTempPath(), $"messenger-test-{Guid.NewGuid():N}.db")}");
            builder.UseSetting("JWTKey:Secret", "test-only-secret-with-more-than-thirty-two-characters");
            builder.UseSetting("JWTKey:ValidIssuer", "tests");
            builder.UseSetting("JWTKey:ValidAudience", "tests");
            builder.UseSetting("Agora:AppId", new string('a', 32));
            builder.UseSetting("Agora:AppCertificate", new string('b', 32));
        }
    }

    private static async Task<JsonElement> Json(HttpResponseMessage response)
    {
        var content = await response.Content.ReadAsStringAsync();
        Assert.True(response.IsSuccessStatusCode, $"{response.StatusCode}: {content}");
        return JsonDocument.Parse(content).RootElement.Clone();
    }

    private static async Task<JsonElement> Register(HttpClient client, string phone, string email)
    {
        return await Json(await client.PostAsJsonAsync("/api/Authenticate/register", new
        {
            name = "Test User", email, password = "password123", phone
        }));
    }

    [Fact]
    public async Task TwoAccountsReceiveRealtimeMessagesAndNegotiateTheSameCallChannel()
    {
        using var factory = new ApiFactory();
        using var client = factory.CreateClient();
        var a = await Register(client, "0912345678", "a@example.com");
        var b = await Register(client, "0987654321", "b@example.com");
        var aid = a.GetProperty("user").GetProperty("uid").GetString()!;
        var bid = b.GetProperty("user").GetProperty("uid").GetString()!;
        var atoken = a.GetProperty("token").GetString()!;
        var btoken = b.GetProperty("token").GetString()!;
        HubConnection Connect(string token) => new HubConnectionBuilder().WithUrl(
            new Uri(client.BaseAddress!, "/hubs/chat"), options =>
            {
                options.AccessTokenProvider = () => Task.FromResult<string?>(token);
                options.Transports = HttpTransportType.LongPolling;
                options.HttpMessageHandlerFactory = _ => factory.Server.CreateHandler();
            }).Build();
        await using var ahub = Connect(atoken);
        await using var bhub = Connect(btoken);
        var incoming = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        var message = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        var accepted = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        var ended = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        bhub.On<JsonElement>("IncomingCall", c => incoming.TrySetResult(c));
        bhub.On<JsonElement>("NewMessage", m => message.TrySetResult(m));
        ahub.On<JsonElement>("CallStatusChanged", c =>
        {
            if (c.GetProperty("status").GetString() == "accepted") accepted.TrySetResult(c);
            if (c.GetProperty("status").GetString() == "ended") ended.TrySetResult(c);
        });
        await ahub.StartAsync();
        await bhub.StartAsync();
        var chatId = string.CompareOrdinal(aid, bid) < 0 ? $"{aid}_{bid}" : $"{bid}_{aid}";
        await bhub.InvokeAsync("JoinChat", chatId);
        client.DefaultRequestHeaders.Authorization = new("Bearer", atoken);
        var readiness = await Json(await client.GetAsync("/api/Rtc/status"));
        Assert.True(readiness.GetProperty("configured").GetBoolean());
        await Json(await client.PostAsJsonAsync($"/api/Chats/{bid}/messages",
            new { text = "Hello from device A", type = "text", isVideo = false }));
        Assert.Equal("Hello from device A", (await message.Task.WaitAsync(TimeSpan.FromSeconds(10))).GetProperty("text").GetString());
        var call = await Json(await client.PostAsJsonAsync("/api/Calls", new { peerId = bid, isVideo = true }));
        var id = call.GetProperty("id").GetString();
        Assert.Equal(id, (await incoming.Task.WaitAsync(TimeSpan.FromSeconds(10))).GetProperty("id").GetString());
        var unauthorizedAccept = await client.PutAsJsonAsync($"/api/Calls/{id}/status", new { status = "accepted" });
        Assert.Equal(HttpStatusCode.Forbidden, unauthorizedAccept.StatusCode);
        var artc = await Json(await client.PostAsJsonAsync("/api/Rtc/token", new { callId = id }));
        client.DefaultRequestHeaders.Authorization = new("Bearer", btoken);
        await Json(await client.PutAsJsonAsync($"/api/Calls/{id}/status", new { status = "accepted" }));
        await accepted.Task.WaitAsync(TimeSpan.FromSeconds(10));
        var brtc = await Json(await client.PostAsJsonAsync("/api/Rtc/token", new { callId = id }));
        Assert.Equal(artc.GetProperty("channelId").GetString(), brtc.GetProperty("channelId").GetString());
        Assert.Equal(artc.GetProperty("appId").GetString(), brtc.GetProperty("appId").GetString());
        Assert.NotEqual(artc.GetProperty("uid").GetUInt32(), brtc.GetProperty("uid").GetUInt32());
        await Json(await client.PutAsJsonAsync($"/api/Calls/{id}/status", new { status = "ended" }));
        await ended.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Equal(HttpStatusCode.Forbidden,
            (await client.PostAsJsonAsync("/api/Rtc/token", new { callId = id })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict,
            (await client.PutAsJsonAsync($"/api/Calls/{id}/status", new { status = "accepted" })).StatusCode);
    }

    [Fact]
    public async Task RegistrationWorksWithoutOtpAndDoesNotMarkEmailAsVerified()
    {
        using var factory = new ApiFactory();
        using var client = factory.CreateClient();
        var auth = await Register(client, "0912345678", "a@example.com");
        Assert.False(string.IsNullOrEmpty(auth.GetProperty("token").GetString()));
        using var scope = factory.Services.CreateScope();
        var users = scope.ServiceProvider.GetRequiredService<Microsoft.AspNetCore.Identity.UserManager<MessengerCallApi.Models.AppUser>>();
        var user = await users.FindByEmailAsync("a@example.com");
        Assert.False(user!.EmailConfirmed);
        Assert.False(user.PhoneNumberConfirmed);
        var login = await Json(await client.PostAsJsonAsync("/api/Authenticate/login",
            new { email = "a@example.com", password = "password123" }));
        Assert.False(string.IsNullOrEmpty(login.GetProperty("token").GetString()));
        var otp = await client.PostAsJsonAsync("/api/Authenticate/email/send-otp", new { email = "a@example.com" });
        Assert.Equal(HttpStatusCode.NotFound, otp.StatusCode);
    }

    [Fact]
    public async Task CallTokenIsRestrictedAndAvatarSurvivesProfileRefresh()
    {
        using var factory = new ApiFactory();
        using var client = factory.CreateClient();
        var a = await Register(client, "0912345678", "a@example.com");
        var b = await Register(client, "0987654321", "b@example.com");
        var c = await Register(client, "0901234567", "c@example.com");
        client.DefaultRequestHeaders.Authorization = new("Bearer", a.GetProperty("token").GetString());
        var call = await Json(await client.PostAsJsonAsync("/api/Calls", new
            { peerId = b.GetProperty("user").GetProperty("uid").GetString(), isVideo = true }));
        var callId = call.GetProperty("id").GetString();
        var rtc = await Json(await client.PostAsJsonAsync("/api/Rtc/token", new { callId }));
        Assert.StartsWith("007", rtc.GetProperty("token").GetString());
        Assert.True(rtc.GetProperty("uid").GetUInt32() > 0);

        using var form = new MultipartFormDataContent();
        var png = new ByteArrayContent(Convert.FromBase64String(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="));
        png.Headers.ContentType = new MediaTypeHeaderValue("image/png");
        form.Add(png, "image", "test.png");
        await Json(await client.PostAsync("/api/Users/me/avatar", form));
        var me = await Json(await client.GetAsync("/api/Authenticate/me"));
        Assert.Contains(".png", me.GetProperty("avatarUrl").GetString());
        Assert.Equal(HttpStatusCode.OK,
            (await client.GetAsync(me.GetProperty("avatarUrl").GetString())).StatusCode);

        var peerId = b.GetProperty("user").GetProperty("uid").GetString();
        using var imageForm = new MultipartFormDataContent();
        imageForm.Add(new ByteArrayContent(await png.ReadAsByteArrayAsync()), "image", "chat.png");
        var sentImage = await Json(await client.PostAsync($"/api/Chats/{peerId}/image", imageForm));
        Assert.Equal("image", sentImage.GetProperty("type").GetString());
        Assert.Equal(HttpStatusCode.OK,
            (await client.GetAsync(sentImage.GetProperty("text").GetString())).StatusCode);
        await Json(await client.PostAsJsonAsync($"/api/Chats/{peerId}/messages",
            new { text = "10.762622,106.660172", type = "location", isVideo = false }));
        client.DefaultRequestHeaders.Authorization = new("Bearer", b.GetProperty("token").GetString());
        var senderId = a.GetProperty("user").GetProperty("uid").GetString();
        var messages = await Json(await client.GetAsync($"/api/Chats/{senderId}/messages"));
        Assert.Contains(messages.EnumerateArray(), m => m.GetProperty("type").GetString() == "image");
        Assert.Contains(messages.EnumerateArray(), m => m.GetProperty("type").GetString() == "location");

        client.DefaultRequestHeaders.Authorization = new("Bearer", c.GetProperty("token").GetString());
        var forbidden = await client.PostAsJsonAsync("/api/Rtc/token", new { callId });
        Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);
    }
}
